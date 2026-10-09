require "test_helper"

class TransferTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @outflow = transactions(:transfer_out)
    @inflow = transactions(:transfer_in)
  end

  test "transfer destroyed if either transaction is destroyed" do
    assert_difference "Transfer.count", -1 do
      assert_difference "Transaction.count", -1 do
        assert_difference "Entry.count", -1 do
          @outflow.entry.destroy
        end
      end
    end
  end

  test "destroy! clears the idempotency key so a retried request can create a new transfer" do
    idempotency_key = SecureRandom.uuid

    transfer = Transfer::Creator.new(
      family: families(:dylan_family),
      source_account_id: accounts(:depository).id,
      destination_account_id: accounts(:credit_card).id,
      date: Date.current,
      amount: 100,
      idempotency_key: idempotency_key
    ).create

    transfer.destroy!

    assert_nil transfer.outflow_transaction.entry.reload.idempotency_key
    assert_nil transfer.inflow_transaction.entry.reload.idempotency_key

    # A retry of the original create request (e.g. the user resubmits after
    # rejecting/undoing the first transfer) must not find a stale entry with
    # this key and raise RecordNotUnique - it should create a fresh transfer.
    assert_difference "Transfer.count", 1 do
      Transfer::Creator.new(
        family: families(:dylan_family),
        source_account_id: accounts(:depository).id,
        destination_account_id: accounts(:credit_card).id,
        date: Date.current,
        amount: 100,
        idempotency_key: idempotency_key
      ).create
    end
  end

  test "transfer has different accounts, opposing amounts, and within 4 days of each other" do
    outflow_entry = create_transaction(date: 1.day.ago.to_date, account: accounts(:depository), amount: 500)
    inflow_entry = create_transaction(date: Date.current, account: accounts(:credit_card), amount: -500)

    assert_difference -> { Transfer.count } => 1 do
      Transfer.create!(
        inflow_transaction: inflow_entry.transaction,
        outflow_transaction: outflow_entry.transaction,
      )
    end
  end

  test "transfer cannot have 2 transactions from the same account" do
    outflow_entry = create_transaction(date: Date.current, account: accounts(:depository), amount: 500)
    inflow_entry = create_transaction(date: 1.day.ago.to_date, account: accounts(:depository), amount: -500)

    transfer = Transfer.new(
      inflow_transaction: inflow_entry.transaction,
      outflow_transaction: outflow_entry.transaction,
    )

    assert_no_difference -> { Transfer.count } do
      transfer.save
    end

    assert_equal "Must be from different accounts", transfer.errors.full_messages.first
  end

  test "Transfer transactions must have opposite amounts" do
    outflow_entry = create_transaction(date: Date.current, account: accounts(:depository), amount: 500)
    inflow_entry = create_transaction(date: Date.current, account: accounts(:credit_card), amount: -400)

    transfer = Transfer.new(
      inflow_transaction: inflow_entry.transaction,
      outflow_transaction: outflow_entry.transaction,
    )

    assert_no_difference -> { Transfer.count } do
      transfer.save
    end

    assert_equal "Must have opposite amounts", transfer.errors.full_messages.first
  end

  test "transfer dates must be within 4 days of each other" do
    outflow_entry = create_transaction(date: Date.current, account: accounts(:depository), amount: 500)
    inflow_entry = create_transaction(date: 5.days.ago.to_date, account: accounts(:credit_card), amount: -500)

    transfer = Transfer.new(
      inflow_transaction: inflow_entry.transaction,
      outflow_transaction: outflow_entry.transaction,
    )

    assert_no_difference -> { Transfer.count } do
      transfer.save
    end

    assert_equal "Must be within 4 days", transfer.errors.full_messages.first
  end

  test "transfer must be from the same family" do
    family1 = families(:empty)
    family2 = families(:dylan_family)

    family1_account = family1.accounts.create!(name: "Family 1 Account", balance: 5000, currency: "USD", accountable: Depository.new)
    family2_account = family2.accounts.create!(name: "Family 2 Account", balance: 5000, currency: "USD", accountable: Depository.new)

    outflow_txn = create_transaction(date: Date.current, account: family1_account, amount: 500)
    inflow_txn = create_transaction(date: Date.current, account: family2_account, amount: -500)

    transfer = Transfer.new(
      inflow_transaction: inflow_txn.transaction,
      outflow_transaction: outflow_txn.transaction,
    )

    assert transfer.invalid?
    assert_equal "Must be from same family", transfer.errors.full_messages.first
  end

  test "transaction can only belong to one transfer" do
    outflow_entry = create_transaction(date: Date.current, account: accounts(:depository), amount: 500)
    inflow_entry1 = create_transaction(date: Date.current, account: accounts(:credit_card), amount: -500)
    inflow_entry2 = create_transaction(date: Date.current, account: accounts(:credit_card), amount: -500)

    Transfer.create!(inflow_transaction: inflow_entry1.transaction, outflow_transaction: outflow_entry.transaction)

    assert_raises ActiveRecord::RecordInvalid do
      Transfer.create!(inflow_transaction: inflow_entry2.transaction, outflow_transaction: outflow_entry.transaction)
    end
  end

  test "crossing into an outside-finances account is an expense boundary" do
    source = accounts(:depository)
    destination = accounts(:credit_card)
    destination.update!(financial_treatment: "outside_finances")

    assert_equal "transfer_to_excluded", Transfer.outflow_kind_for(source, destination)
    assert_equal "transfer_to_excluded", Transfer.inflow_kind_for(source, destination)
  end

  test "crossing out of an outside-finances account is an income boundary" do
    source = accounts(:depository)
    destination = accounts(:credit_card)
    source.update!(financial_treatment: "outside_finances")

    assert_equal "transfer_from_excluded", Transfer.outflow_kind_for(source, destination)
    assert_equal "transfer_from_excluded", Transfer.inflow_kind_for(source, destination)
  end

  test "changing financial treatment reclassifies existing transfers" do
    transfer = transfers(:one)
    destination = transfer.to_account

    destination.update!(financial_treatment: "outside_finances")
    assert_equal "transfer_to_excluded", transfer.outflow_transaction.reload.kind
    assert_equal "transfer_to_excluded", transfer.inflow_transaction.reload.kind

    destination.update!(financial_treatment: "included")
    assert_equal "cc_payment", transfer.outflow_transaction.reload.kind
    assert_equal "funds_movement", transfer.inflow_transaction.reload.kind
  end

  test "outflow_kind_for returns investment_contribution for investment accounts" do
    assert_equal "investment_contribution", Transfer.outflow_kind_for(accounts(:depository), accounts(:investment))
  end

  test "outflow_kind_for returns investment_contribution for crypto accounts" do
    assert_equal "investment_contribution", Transfer.outflow_kind_for(accounts(:depository), accounts(:crypto))
  end

  test "outflow_kind_for returns loan_payment for loan accounts" do
    assert_equal "loan_payment", Transfer.outflow_kind_for(accounts(:depository), accounts(:loan))
  end

  test "outflow_kind_for returns cc_payment for credit card accounts" do
    assert_equal "cc_payment", Transfer.outflow_kind_for(accounts(:depository), accounts(:credit_card))
  end

  test "outflow_kind_for returns funds_movement for depository accounts" do
    assert_equal "funds_movement", Transfer.outflow_kind_for(accounts(:investment), accounts(:depository))
  end

  test "has_source_fee? returns true when source fee present" do
    transfer = transfers(:one)
    entry = accounts(:depository).entries.create!(name: "Fee", date: Date.current, amount: 5, currency: "USD", entryable: Transaction.new(kind: "standard"))
    transfer.fee_transactions << entry.entryable
    assert transfer.has_source_fee?
    assert transfer.has_fees?
  end

  test "has_destination_fee? returns true when destination fee present" do
    transfer = transfers(:one)
    entry = accounts(:credit_card).entries.create!(name: "Fee", date: Date.current, amount: 5, currency: "USD", entryable: Transaction.new(kind: "standard"))
    transfer.fee_transactions << entry.entryable
    assert transfer.has_destination_fee?
    assert transfer.has_fees?
  end

  test "has_fees? returns false when no fees" do
    transfer = transfers(:one)
    refute transfer.has_fees?
  end

  test "total_fee sums source and destination fees" do
    transfer = transfers(:one)
    entry1 = accounts(:depository).entries.create!(name: "Fee", date: Date.current, amount: 3, currency: "USD", entryable: Transaction.new(kind: "standard"))
    entry2 = accounts(:credit_card).entries.create!(name: "Fee", date: Date.current, amount: 2, currency: "USD", entryable: Transaction.new(kind: "standard"))
    transfer.fee_transactions << entry1.entryable << entry2.entryable
    assert_equal 5, transfer.total_fee
  end

  test "fees retain original currencies and never combine a mixed currency numeric total" do
    transfer = transfers(:one)
    source = transfer.from_account.entries.create!(name: "EUR fee", date: Date.current, amount: 2, currency: "EUR", entryable: Transaction.new)
    destination = transfer.to_account.entries.create!(name: "USD fee", date: Date.current, amount: 3, currency: "USD", entryable: Transaction.new)
    transfer.fee_transactions << [ source.entryable, destination.entryable ]

    assert_nil transfer.total_fee
    assert_equal({ "EUR" => 2, "USD" => 3 }, transfer.fees_by_currency)
    assert_equal "EUR", transfer.fees_by_leg.fetch(:source).first.currency.iso_code
    assert_equal "USD", transfer.fees_by_leg.fetch(:destination).first.currency.iso_code
    assert_nil transfer.source_total_money
  end

  test "fee parent and paired transfer are distinct relationships" do
    transfer = transfers(:one)
    fee = create_transaction(account: transfer.from_account, amount: 5).entryable
    transfer.fee_transactions << fee

    assert_equal transfer, fee.reload.fee_transfer
    assert_nil fee.paired_transfer
    assert_nil fee.transfer
    assert_equal transfer, transfer.outflow_transaction.paired_transfer
    assert_equal transfer, transfer.outflow_transaction.transfer
    assert_nil transfer.outflow_transaction.fee_transfer
    assert_equal transfer.id, fee.attributes["transfer_id"]
  end

  test "deleting a fee preserves the paired transfer and its entries" do
    transfer = transfers(:one)
    fee = create_transaction(account: transfer.from_account, amount: 5).entryable
    transfer.fee_transactions << fee

    assert_no_difference "Transfer.count" do
      fee.entry.destroy!
    end

    assert transfer.reload.inflow_transaction.entry.present?
    assert transfer.outflow_transaction.entry.present?
    assert_empty transfer.fee_transactions
  end

  test "rejecting a paired transfer removes its fees and preserves ordinary legs" do
    transfer = transfers(:one)
    fee_entry = create_transaction(account: transfer.from_account, amount: 5)
    transfer.fee_transactions << fee_entry.entryable
    inflow_entry = transfer.inflow_transaction.entry
    outflow_entry = transfer.outflow_transaction.entry

    transfer.reject!

    assert_not Entry.exists?(fee_entry.id)
    assert_equal "standard", inflow_entry.reload.entryable.kind
    assert_equal "standard", outflow_entry.reload.entryable.kind
    assert_nil inflow_entry.entryable.paired_transfer
    assert_nil outflow_entry.entryable.paired_transfer
  end

  test "reclassification derives both kinds and preserves manual categories" do
    transfer = transfers(:one)
    outflow_category = transfer.outflow_transaction.category_id
    inflow_category = transfer.inflow_transaction.category_id
    transfer.outflow_transaction.update_column(:kind, "standard")
    transfer.inflow_transaction.update_column(:kind, "standard")

    transfer.reclassify_transactions!

    assert_equal Transfer.outflow_kind_for(transfer.from_account, transfer.to_account), transfer.outflow_transaction.reload.kind
    assert_equal Transfer.inflow_kind_for(transfer.from_account, transfer.to_account), transfer.inflow_transaction.reload.kind
    assert_equal outflow_category, transfer.outflow_transaction.category_id
    assert_equal inflow_category, transfer.inflow_transaction.category_id
  end

  test "failed reclassification rolls back both legs even inside an outer transaction" do
    transfer = transfers(:one)
    transfer.outflow_transaction.update_column(:kind, "standard")
    transfer.inflow_transaction.expects(:update!).raises(ActiveRecord::RecordInvalid.new(transfer.inflow_transaction))

    assert_raises(ActiveRecord::RecordInvalid) { transfer.reclassify_transactions! }

    assert_equal "standard", transfer.outflow_transaction.reload.kind
  end
end
