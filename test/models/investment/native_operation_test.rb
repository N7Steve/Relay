require "test_helper"

class Investment::NativeOperationTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @family.update!(locale: "es")
    @bank = @family.accounts.create!(name: "Banco", balance: 1000, currency: "USD", accountable: Depository.new)
    @portfolio = @family.accounts.create!(name: "Cartera", balance: 0, currency: "USD", accountable: Investment.new(subtype: "roboadvisor"))
    @category = @family.categories.create!(name: "Supermercado")
  end

  test "contributions have authoritative names and no category on either leg" do
    transfer = create_transfer(@bank, @portfolio)
    assert_equal "Aportación · Cartera", transfer.name
    assert_not transfer.categorizable?
    assert_equal "investment_contribution", transfer.outflow_transaction.kind
    assert_equal "funds_movement", transfer.inflow_transaction.kind
    assert_equal 100, transfer.outflow_transaction.entry.amount
    [ transfer.outflow_transaction, transfer.inflow_transaction ].each do |transaction|
      assert_nil transaction.reload.category_id
      assert_equal "Aportación · Cartera", transaction.entry.reload.name
      assert_equal "contribution", transaction.extra["native_managed_operation"]
      assert_not Entry.uncategorized_transactions.exists?(transaction.entry.id)
      assert_not Transaction::Search.new(@family, filters: { categories: [ Category::UNCATEGORIZED_FILTER_VALUE ] })
        .transactions_scope.exists?(transaction.id)
    end
  end

  test "direct edits bulk edits and enrichment cannot change the operation identity" do
    transfer = create_transfer(@bank, @portfolio)
    transaction = transfer.outflow_transaction
    transaction.entry.update!(name: "Compras", notes: "Keep notes")
    transaction.update!(category: @category)
    transaction.enrich_attribute(:category_id, @category.id, source: "rule", ignore_locks: true)
    Entry.where(id: transaction.entry.id).bulk_update!({ name: "Another title", category_id: @category.id })
    assert_nil transaction.reload.category_id
    assert_equal "Aportación · Cartera", transaction.entry.reload.name
    assert_equal "Keep notes", transaction.entry.notes
  end

  test "withdrawals inter-portfolio transfers and account renames remain canonical" do
    withdrawal = create_transfer(@portfolio, @bank)
    assert_equal "Retirada · Cartera", withdrawal.name
    other = @family.accounts.create!(name: "Segunda", balance: 0, currency: "USD", accountable: Investment.new(tracking_mode: "managed", subtype: "pension"))
    between = create_transfer(@portfolio, other)
    assert_equal "Traspaso · Cartera → Segunda", between.name
    standalone = @portfolio.entries.create!(name: "Legacy contribution", date: Date.current, amount: -50,
      currency: "USD", entryable: Transaction.new(kind: "investment_contribution"))
    @portfolio.update!(name: "Renombrada")
    assert_equal "Retirada · Renombrada", withdrawal.outflow_transaction.entry.reload.name
    assert_equal "Traspaso · Renombrada → Segunda", between.inflow_transaction.entry.reload.name
    assert_equal "Aportación · Renombrada", standalone.reload.name
  end

  test "ordinary transfers retain their customizable name and category" do
    other = @family.accounts.create!(name: "Savings", balance: 0, currency: "USD", accountable: Depository.new)
    transfer = create_transfer(@bank, other)
    assert transfer.categorizable?
    assert_equal "Supermercado", transfer.name
    assert_equal @category, transfer.outflow_transaction.category
    assert_nil transfer.outflow_transaction.extra["native_managed_operation"]
  end

  test "scheduled contribution updates preserve the native identity on both legs" do
    payment = @family.scheduled_payments.create!(account: @bank, target_account: @portfolio,
      title: "Monthly savings", amount: 100, currency: "USD", payment_type: "transfer",
      frequency: "monthly", frequency_day: 1, start_date: Date.current, next_run_date: Date.current)
    occurrence = payment.generate_pending_entry!
    occurrence.confirm!
    payment.update!(title: "Supermercado", category: @category)
    payment.sync_confirmed_entries!
    [ occurrence.reload.entry, occurrence.transfer_entry ].each do |entry|
      assert_equal "Aportación · Cartera", entry.reload.name
      assert_nil entry.transaction.reload.category_id
    end
  end

  test "valuations always use their date while preserving notes and signed deltas" do
    entry = @portfolio.entries.create!(date: Date.current, name: "Valores agosto", amount: -114.71,
      currency: "USD", notes: "Original note", entryable: Transaction.new(kind: "investment_value_adjustment", category: @category))
    assert_equal "Valoración #{Date.current.strftime('%d/%m/%Y')}", entry.name
    assert_nil entry.transaction.category_id
    entry.update!(name: "Groceries", date: Date.yesterday)
    assert_equal "Valoración #{Date.yesterday.strftime('%d/%m/%Y')}", entry.reload.name
    assert_equal BigDecimal("-114.71"), entry.amount
    assert_equal "Original note", entry.notes
  end

  test "unlinking removes the native marker and restores ordinary editability" do
    transfer = create_transfer(@bank, @portfolio)
    transaction = transfer.outflow_transaction
    transfer.reject!
    transaction.reload
    transaction.entry.update!(name: "Independent transaction")
    transaction.update!(category: @category)
    assert_equal "Independent transaction", transaction.entry.reload.name
    assert_equal @category, transaction.reload.category
    assert_nil transaction.extra["native_managed_operation"]
  end

  private
    def create_transfer(from, to)
      Transfer::Creator.new(family: @family, source_account_id: from.id, destination_account_id: to.id,
        amount: 100, date: Date.current, name: "Supermercado", category_id: @category.id).create
    end
end
