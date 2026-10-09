require "test_helper"

class Entry::FinancialEligibilityTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @account = families(:dylan_family).accounts.create!(
      name: "Eligibility account", accountable: Depository.new, currency: "USD", balance: 0
    )
  end

  test "analytics exclusion retains balance movements without adding import protection" do
    ordinary = create_transaction(account: @account, amount: 100)
    excluded = create_transaction(account: @account, amount: 1_000, excluded: true)

    assert_equal [ ordinary.id, excluded.id ].sort, @account.entries.eligible_for_balance.pluck(:id).sort
    assert_equal [ ordinary.id ], @account.entries.eligible_for_forecast_history.pluck(:id)
    assert_equal 1_100, Balance::SyncCache.new(@account).get_entries(Date.current).sum(&:amount)
    assert_not excluded.protected_from_sync?
  end

  test "pending flags from current and historical providers do not enter either history" do
    posted = create_transaction(account: @account)
    Transaction::PENDING_PROVIDERS.each do |provider|
      create_transaction(account: @account, entryable: Transaction.new(extra: { provider => { "pending" => true } }))
    end

    assert_equal [ posted.id ], @account.entries.eligible_for_balance.pluck(:id)
    assert_equal [ posted.id ], @account.entries.eligible_for_forecast_history.pluck(:id)
  end

  test "split counts children once for balances and omits analytically excluded children from forecasts" do
    parent = create_transaction(account: @account, amount: 100)
    included, excluded = parent.split!([
      { name: "Included part", amount: 60 },
      { name: "Excluded part", amount: 40, excluded: true }
    ])

    assert_equal [ included.id, excluded.id ].sort, @account.entries.eligible_for_balance.pluck(:id).sort
    assert_equal [ included.id ], @account.entries.eligible_for_forecast_history.pluck(:id)
    assert_equal 100, Balance::SyncCache.new(@account).get_entries(Date.current).sum(&:amount)

    parent.unsplit!

    assert_equal [ parent.id ], @account.entries.eligible_for_balance.pluck(:id)
    assert_equal [ parent.id ], @account.entries.eligible_for_forecast_history.pluck(:id)
  end

  test "forecast selection leaves kind and statistical behavior to the consumer" do
    entries = Transaction.kinds.keys.map { |kind| create_transaction(account: @account, kind: kind) }
    entries << create_transaction(account: @account, entryable: Transaction.new(forecast_behavior: "irregular_recurring"))

    assert_equal entries.map(&:id).sort, @account.entries.eligible_for_balance.pluck(:id).sort
    assert_equal entries.map(&:id).sort, @account.entries.eligible_for_forecast_history.pluck(:id).sort
  end

  test "income statement preserves budget classification independently of balance eligibility" do
    create_transaction(account: @account, amount: 100)
    create_transaction(account: @account, amount: 50, entryable: Transaction.new(forecast_behavior: "irregular_recurring"))
    create_transaction(account: @account, amount: 200, kind: "loan_payment")
    create_transaction(account: @account, amount: 300, kind: "transfer_to_excluded")
    create_transaction(account: @account, amount: -400, kind: "transfer_from_excluded")
    create_transaction(account: @account, amount: 1_000, excluded: true)
    %w[funds_movement cc_payment investment_contribution one_time].each do |kind|
      create_transaction(account: @account, amount: 1_000, kind: kind)
    end

    totals = IncomeStatement::Totals.new(
      @account.family, transactions_scope: @account.transactions,
      date_range: Date.current..Date.current, include_trades: false
    ).call

    assert_equal 650, totals.select { |row| row.classification == "expense" }.sum(&:total)
    assert_equal 400, totals.select { |row| row.classification == "income" }.sum(&:total)
    assert_equal 5_250, Balance::SyncCache.new(@account).get_entries(Date.current).sum(&:amount)
  end

  test "valuation and trade remain balance inputs while account and date scopes are preserved" do
    transaction = create_transaction(account: @account)
    valuation = create_valuation(account: @account)
    trade = create_trade(securities(:aapl), account: @account, qty: 1, price: 10, date: Date.current)
    create_transaction(account: accounts(:depository))
    create_transaction(account: @account, date: 2.days.ago.to_date)

    recent = @account.entries.where(date: 1.day.ago.to_date..Date.current)

    assert_equal [ transaction.id, valuation.id, trade.id ].sort, recent.eligible_for_balance.pluck(:id).sort
    assert_equal [ transaction.id ], recent.eligible_for_forecast_history.pluck(:id)
    assert_equal valuation.id, Balance::SyncCache.new(@account).get_valuation(valuation.date).id
  end

  test "exceptional split children retain forecast and budget exclusion without losing balance" do
    parent = create_transaction(account: @account, amount: 100, entryable: Transaction.new(forecast_behavior: "exceptional_once"))
    children = parent.split!([
      { name: "First part", amount: 60 },
      { name: "Second part", amount: 40 }
    ])

    children.each do |child|
      assert_predicate child.entryable, :standard?
      assert_predicate child.entryable, :forecast_exceptional_once?
    end
    assert_empty @account.transactions.budget_reportable
    assert_equal 100, Balance::SyncCache.new(@account).get_entries(Date.current).sum(&:amount)
  end
end
