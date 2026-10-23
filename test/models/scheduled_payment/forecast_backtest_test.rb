require "test_helper"

class ScheduledPayment::ForecastBacktestTest < ActiveSupport::TestCase
  fixtures :families, :users, :accounts

  [ Date.new(2026, 1, 1), Date.new(2026, 3, 31), Date.new(2028, 2, 29) ].product([ 1, 15 ]).each do |cutoff, month_start_day|
    test "historical fit respects cutoff #{cutoff} with month start #{month_start_day}" do
      family = families(:dylan_family)
      family.update!(month_start_day: month_start_day)
      user = users(:family_admin)
      account = accounts(:depository)
      before = Transaction.create!
      after = Transaction.create!
      account.entries.create!(
        # Forecast history uses completed family months, not the partial month
        # containing the cutoff. Keep this observation inside that history on
        # every calendar day, rather than accidentally testing an empty sample.
        date: family.custom_month_start_for(cutoff) - 10.days, amount: 100, currency: account.currency,
        name: "Before cutoff", entryable: before
      )
      account.entries.create!(
        date: cutoff + 10.days, amount: 50_000, currency: account.currency,
        name: "After cutoff", entryable: after
      )
      partial = account.entries.create!(
        date: cutoff, amount: 90_000, currency: account.currency,
        name: "Incomplete month", entryable: Transaction.new
      )

      forecast = ScheduledPayment::WealthForecast.new(
        family:, user:, horizon_months: 3, as_of: cutoff, include_agenda: false
      )

      history = forecast.send(:historical_entries)
      assert_includes history.map(&:id), before.entry.id
      assert_operator history.map(&:date).max, :<=, cutoff
      assert_not_includes history.map(&:id), after.entry.id
      assert_not_includes history.map(&:id), partial.id
    end
  end

  test "historical fit with no completed observations has no estimated cashflow" do
    user = users(:empty)
    forecast = ScheduledPayment::WealthForecast.new(
      family: user.family, user: user, as_of: Date.new(2026, 3, 31), include_agenda: false
    )

    assert_empty forecast.send(:historical_entries)
    assert_equal 0, forecast.history_months
    assert_equal 0, forecast.historical_monthly_savings.amount
  end

  test "reports bias mae and coverage for both models and required horizons" do
    backtest = ScheduledPayment::ForecastBacktest.new(
      family: families(:dylan_family), user: users(:family_admin), cutoffs: []
    )

    results = backtest.call

    assert_equal 6, results.size
    assert_equal %i[v1 v2], results.map(&:model).uniq.sort
    assert_equal [ 3, 6, 12 ], results.map(&:horizon_months).uniq.sort
    assert results.all? { |result| result.samples.zero? && result.bias.nil? && result.mae.nil? && result.coverage.nil? }
  end

  test "passes the calibrated cashflow z score to V2 forecasts" do
    backtest = ScheduledPayment::ForecastBacktest.new(
      family: families(:dylan_family), user: users(:family_admin), cutoffs: [], cashflow_scenario_z: 1.25
    )

    assert_equal 1.25, backtest.cashflow_scenario_z
  end
end
