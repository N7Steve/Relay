require "test_helper"

class Investment::ValueUpdateTest < ActiveSupport::TestCase
  setup do
    @account = families(:empty).accounts.create!(name: "Managed", balance: 1000, currency: "USD",
      accountable: Investment.new(subtype: "roboadvisor"))
    @start = Date.current - 30
    @account.entries.create!(date: @start, amount: 1000, currency: "USD", name: "Opening",
      entryable: Valuation.new(kind: "opening_anchor"))
  end

  test "records the absolute target and only the market difference after same-day contributions" do
    movement(-300, @start + 1, kind: "investment_contribution")
    update = Investment::ValueUpdate.new(account: @account, date: @start + 1, amount: "1414.71")
    assert update.save, update.errors.full_messages.to_sentence
    assert_equal BigDecimal("-114.71"), update.entry.amount
    assert_equal BigDecimal("1414.71"), update.entry.transaction.investment_value_target
    assert_equal BigDecimal("1414.71"), @account.reload.balance
    assert_equal BigDecimal("114.71"), Investment::RoboadvisorPerformance.new(@account).total_profit_loss
    assert_not Transaction.budget_reportable.exists?(update.entry.entryable_id)
  end

  test "repeated submissions and corrections reuse the target without duplicating its effect" do
    2.times do
      update = Investment::ValueUpdate.new(account: @account, date: @start + 1, amount: 1100)
      assert update.save, update.errors.full_messages.to_sentence
    end
    assert_equal 1, @account.transactions.where(kind: "investment_value_adjustment").count
    update = Investment::ValueUpdate.new(account: @account, date: @start + 1, amount: 950)
    assert update.save, update.errors.full_messages.to_sentence
    assert_equal 50, update.entry.amount
    assert_equal 950, @account.reload.balance
  end

  test "backfilled contributions change the delta while preserving the declared target" do
    update = Investment::ValueUpdate.new(account: @account, date: @start + 3, amount: 1150)
    assert update.save
    movement(-100, @start + 2, kind: "investment_contribution")
    Account::Recalculator.new(@account).recalculate
    assert_equal(-50, update.entry.reload.amount)
    assert_equal 1150, @account.reload.balance
  end

  test "historical deltas remain intact and successive targets reconcile in chronological order" do
    legacy = movement(-40, @start + 1, kind: "investment_value_adjustment")
    later = Investment::ValueUpdate.new(account: @account, date: @start + 5, amount: 1200)
    assert later.save
    earlier = Investment::ValueUpdate.new(account: @account, date: @start + 3, amount: 1100)
    assert earlier.save
    assert_equal(-40, legacy.reload.amount)
    assert_equal(-60, earlier.entry.amount)
    assert_equal(-100, later.entry.reload.amount)
    assert_equal 1200, @account.reload.balance
  end

  test "zero value is valid while invalid values dates and account types do not write" do
    [ -1, "invalid", nil ].each do |amount|
      update = Investment::ValueUpdate.new(account: @account, amount: amount)
      assert_no_difference "Entry.count" do
        assert_not update.save
      end
    end
    update = Investment::ValueUpdate.new(account: @account, amount: 0, date: @start + 1)
    assert update.save
    assert_equal 1000, update.entry.amount
    assert_equal 0, @account.reload.balance
    assert_not Investment::ValueUpdate.new(account: @account, amount: 100, date: Date.tomorrow).save
    assert_not Investment::ValueUpdate.new(account: accounts(:depository), amount: 100).save
  end

  test "missing FX rolls back rather than recording a partial portfolio value" do
    movement(-100, @start + 1, currency: "GBP", kind: "investment_contribution")
    update = Investment::ValueUpdate.new(account: @account, date: @start + 2, amount: 1200)
    assert_no_difference "Entry.count" do
      assert_not update.save
    end
    assert update.errors.any?
  end

  test "absolute targets supersede reconciliations on the same date without losing the old record" do
    reconciliation = @account.entries.create!(date: @start + 2, amount: 1050, currency: "USD", name: "Old observation",
      entryable: Valuation.new(kind: "reconciliation"))
    update = Investment::ValueUpdate.new(account: @account, date: @start + 2, amount: 1150)
    assert update.save, update.errors.full_messages.to_sentence
    assert_equal(-150, update.entry.amount)
    assert_equal 1150, @account.reload.balance
    assert_equal 1050, reconciliation.reload.amount
    assert_equal 150, Investment::RoboadvisorPerformance.new(@account).total_profit_loss
  end

  test "reverse histories retain native targets across repeated recalculations and later updates" do
    @account.update!(reverse_balance_history: true)
    @account.entries.create!(date: @start + 1, amount: 1000, currency: "USD", name: "Current",
      entryable: Valuation.new(kind: "current_anchor"))
    first = Investment::ValueUpdate.new(account: @account, date: @start + 2, amount: 1100)
    assert first.save, first.errors.full_messages.to_sentence
    movement(-100, @start + 3, kind: "investment_contribution")
    second = Investment::ValueUpdate.new(account: @account, date: @start + 4, amount: 1250)
    assert second.save, second.errors.full_messages.to_sentence
    2.times { Account::Recalculator.new(@account).recalculate }
    assert_equal(-100, first.entry.reload.amount)
    assert_equal(-50, second.entry.reload.amount)
    assert_equal 1250, @account.reload.balance
    assert_equal 150, Investment::RoboadvisorPerformance.new(@account).total_profit_loss
  end

  test "corrections cannot move onto another recorded target date" do
    first = Investment::ValueUpdate.new(account: @account, date: @start + 1, amount: 1100)
    second = Investment::ValueUpdate.new(account: @account, date: @start + 2, amount: 1200)
    assert first.save
    assert second.save
    correction = Investment::ValueUpdate.new(account: @account, entry: second.entry, date: first.date, amount: 1150)
    assert_not correction.save
    assert_equal @start + 2, second.entry.reload.date
    assert_equal 1200, @account.reload.balance
  end

  test "native adjustments cannot be auto-matched into transfers or split" do
    update = Investment::ValueUpdate.new(account: @account, date: Date.current, amount: 1100)
    assert update.save
    other = @account.family.accounts.create!(name: "Bank", balance: 1000, currency: "USD", accountable: Depository.new)
    other.entries.create!(date: Date.current, amount: 100, name: "Coincidental expense", currency: "USD",
      entryable: Transaction.new)
    assert_not update.entry.transaction.splittable?
    assert_empty update.entry.transaction.transfer_match_candidates
    assert_no_difference "Transfer.count" do
      @account.family.auto_match_transfers!
    end
    assert_predicate update.entry.transaction.reload, :investment_value_adjustment?
  end

  test "retained imported balances cannot overwrite a newer local closing value" do
    @account.update!(imported_balance_history: [ { "report_date" => (@start + 1).iso8601, "total" => "1050", "currency" => "USD" } ])
    update = Investment::ValueUpdate.new(account: @account, date: @start + 2, amount: 1150)
    assert update.save, update.errors.full_messages.to_sentence
    Account::Recalculator.new(@account).recalculate
    assert_equal(-100, update.entry.reload.amount)
    assert_equal 1150, @account.reload.balance
    assert_equal 1150, @account.balances.find_by!(date: @start + 2, currency: "USD").balance
    assert_equal 1050, @account.balances.find_by!(date: @start + 1, currency: "USD").balance
  end

  private
    def movement(amount, date, kind: "standard", currency: "USD")
      @account.entries.create!(amount: amount, date: date, currency: currency, name: "Movement",
        entryable: Transaction.new(kind: kind))
    end
end
