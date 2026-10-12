# frozen_string_literal: true

require "test_helper"

class Investment::RoboadvisorPerformanceTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(
      name: "Managed portfolio", balance: 2_030, cash_balance: 0,
      currency: "USD", accountable: Investment.new(subtype: "roboadvisor")
    )
  end

  test "uses Indexa time-weighted index without treating a contribution as return" do
    @account.update!(managed_portfolio: true, imported_performance: {
          return: {
            pl: 30,
            index: { "20260731" => 1.0, "20260815" => 1.01, "20260831" => 1.03 }
          },
          portfolios: [
            { date: "2026-07-31", total_amount: 1_000 },
            { date: "2026-08-15", total_amount: 2_010 },
            { date: "2026-08-31", total_amount: 2_030 }
          ]
      }
    )
    performance = Investment::RoboadvisorPerformance.new(@account)
    period = Date.new(2026, 8, 1)..Date.new(2026, 8, 31)

    assert_in_delta 0.03, performance.rate_for(period), 0.000001
    assert_in_delta 30, performance.total_profit_loss, 0.001
    assert_operator performance.profit_loss_for(period), :<, 50
    assert_operator performance.profit_loss_for(period), :>, 20

    series = performance.profit_loss_series(period: Period.new(start_date: period.begin, end_date: period.end))
    assert_equal [ 0, 10 ], series.values.first(2).map { |point| point.value.amount }
    assert_equal performance.profit_loss_for(period), series.values.last.value.amount
  end

  test "balance-only fallback ignores bootstrap valuation and includes later revaluation" do
    @account.balances.create!(
      date: Date.new(2026, 7, 31), balance: 1_000, currency: "USD",
      cash_adjustments: 1_000
    )
    @account.balances.create!(
      date: Date.new(2026, 8, 31), balance: 1_100, currency: "USD",
      start_cash_balance: 1_000, cash_adjustments: 100
    )

    performance = Investment::RoboadvisorPerformance.new(@account)

    assert_equal 100, performance.total_profit_loss
    assert_equal 100, performance.profit_loss_for(Date.new(2026, 8, 1)..Date.new(2026, 8, 31))
  end

  test "manual performance includes income and fees but excludes capital transfers" do
    @account.balances.create!(
      date: Date.new(2026, 7, 31), balance: 1_000, currency: "USD",
      cash_adjustments: 1_000
    )
    @account.balances.create!(
      date: Date.new(2026, 8, 31), balance: 1_050, currency: "USD",
      start_cash_balance: 1_000, cash_adjustments: 50
    )
    @account.entries.create!(
      name: "Distribution", date: Date.new(2026, 8, 15), amount: -10,
      currency: "USD", entryable: Transaction.new(kind: "standard")
    )
    @account.entries.create!(
      name: "Management fee", date: Date.new(2026, 8, 20), amount: 4,
      currency: "USD", entryable: Transaction.new(kind: "standard")
    )
    @account.entries.create!(
      name: "Contribution", date: Date.new(2026, 8, 10), amount: -500,
      currency: "USD", entryable: Transaction.new(kind: "investment_contribution")
    )
    @account.entries.create!(
      name: "Rebalance purchase", date: Date.new(2026, 8, 12), amount: 700,
      currency: "USD", entryable: Transaction.new(kind: "standard", investment_activity_label: "Buy")
    )
    performance = Investment::RoboadvisorPerformance.new(@account)
    period = Date.new(2026, 8, 1)..Date.new(2026, 8, 31)

    assert_equal 56, performance.profit_loss_for(period)
    assert_in_delta 0.056, performance.rate_for(period), 0.000001
  end

  test "chart isolates contributions withdrawals gains and fees and rebases each period" do
    opening = Date.new(2026, 7, 31)
    @account.balances.create!(date: opening, balance: 1000, currency: "USD", cash_adjustments: 1000)
    @account.balances.create!(date: opening + 1, balance: 1200, currency: "USD", start_cash_balance: 1000, cash_inflows: 200)
    @account.balances.create!(date: opening + 2, balance: 1250, currency: "USD", start_cash_balance: 1200, cash_adjustments: 50)
    @account.balances.create!(date: opening + 3, balance: 1146, currency: "USD", start_cash_balance: 1250, cash_outflows: 104)
    [ [ -200, "investment_contribution", 1 ], [ 100, "funds_movement", 3 ], [ 4, "standard", 3 ] ].each do |amount, kind, offset|
      @account.entries.create!(name: kind, date: opening + offset, amount: amount, currency: "USD", entryable: Transaction.new(kind: kind))
    end
    performance = Investment::RoboadvisorPerformance.new(@account)
    period = Period.new(start_date: opening + 1, end_date: opening + 3)

    assert_equal [ 0, 0, 50, 46 ], performance.profit_loss_series(period: period).map { |point| point.value.amount }

    fee_period = Period.new(start_date: opening + 3, end_date: opening + 3)
    assert_equal [ 0, -4 ], performance.profit_loss_series(period: fee_period).map { |point| point.value.amount }
  end

  test "chart has no fabricated return when there is no history" do
    assert_empty Investment::RoboadvisorPerformance.new(@account).profit_loss_series(period: Period.last_30_days)
  end
end
