require "test_helper"

class Account::RecalculatorTest < ActiveSupport::TestCase
  setup do
    Setting.stubs(:ai_features_enabled?).returns(false)
    ExternalAccess::CAPABILITIES.each do |capability|
      Setting.stubs("external_#{capability}_enabled").returns(false)
    end
    @account = families(:empty).accounts.create!(
      name: "Local account", balance: 1000, cash_balance: 1000,
      currency: "USD", accountable: Depository.new
    )
    @account.entries.create!(name: "Opening", date: Date.current - 2, amount: 1000,
      currency: "USD", entryable: Valuation.new(kind: "opening_anchor"))
  end

  test "manual entries recalculate without any external capability" do
    @account.entries.create!(name: "Expense", date: Date.current - 1, amount: 100,
      currency: "USD", entryable: Transaction.new)
    Account::Recalculator.new(@account).recalculate
    assert_equal 900, @account.reload.balance
    assert_equal 900, @account.balances.order(:date).last.balance
  end

  test "missing FX preserves the last valid balances and fails explicitly" do
    Account::Recalculator.new(@account).recalculate
    before = @account.balances.order(:date).map(&:attributes)
    @account.entries.create!(name: "Foreign expense", date: Date.current - 1, amount: 100,
      currency: "JPY", entryable: Transaction.new)
    assert_raises(Money::ConversionError) { Account::Recalculator.new(@account).recalculate }
    assert_equal before, @account.balances.order(:date).map(&:attributes)
    assert_equal 1000, @account.reload.balance
  end

  test "the existing asynchronous sync job completes local accounting without providers" do
    @account.entries.create!(name: "Income", date: Date.current - 1, amount: -250,
      currency: "USD", entryable: Transaction.new)
    sync = @account.syncs.create!
    SyncJob.perform_now(sync)
    assert sync.reload.completed?
    assert_equal 1250, @account.reload.balance
  end

  test "a suspended connector still uses reverse accounting" do
    @account.stubs(:linked?).returns(true)
    Balance::Materializer.expects(:new).with(@account, strategy: :reverse, window_start_date: nil).returns(
      mock(materialize_balances: nil)
    )
    Account::Recalculator.new(@account).recalculate
  end
end
