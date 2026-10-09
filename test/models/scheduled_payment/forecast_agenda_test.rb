require "test_helper"

class ScheduledPayment::ForecastAgendaTest < ActiveSupport::TestCase
  setup do
    travel_to Date.new(2026, 9, 8)
    @family = families(:empty)
    @user = users(:empty)
    @account = @family.accounts.create!(
      owner: @user, name: "Forecast cash", currency: "USD", balance: 0,
      accountable: Depository.new, status: "active"
    )
    @date = Date.new(2026, 8, 10)
    create_entry(name: "Ordinary income", amount: -200)
  end

  teardown do
    travel_back
  end

  test "both forecasts remove a historical movement once even when two schedules explain it" do
    2.times { create_payment }
    create_entry(name: "  MONTHLY   bill ", amount: 110)

    assert_equal 200, account_forecast.historical_monthly_savings.amount
    assert_equal 200, wealth_forecast.historical_monthly_savings.amount
    month = wealth_forecast.cashflow_diagnostics[:months].last
    assert_equal(-110, month.agenda_removed)
    assert_equal 200, month.adjusted_cashflow
  end

  test "both forecasts require the same currency and convert unexplained history" do
    create_payment
    create_entry(name: "Monthly bill", amount: 100, currency: "EUR")
    ExchangeRate.create!(from_currency: "EUR", to_currency: "USD", date: @date, rate: 1.2)

    assert_equal 80, account_forecast.historical_monthly_savings.amount
    assert_equal 80, wealth_forecast.historical_monthly_savings.amount
  end

  test "explicit Agenda links exclude ordinary history even when heuristic details differ" do
    payment = create_payment
    entry = create_entry(name: "Actual bank description", amount: 1_700)
    payment.scheduled_payment_entries.create!(
      entry: entry, scheduled_date: @date, status: "confirmed"
    )

    assert_equal 200, account_forecast.historical_monthly_savings.amount
    assert_equal 200, wealth_forecast.historical_monthly_savings.amount
    assert_equal(-1_700, wealth_forecast.cashflow_diagnostics[:months].last.agenda_removed)
  end

  test "a matching schedule on another account does not explain this account's history" do
    other_account = @family.accounts.create!(
      owner: @user, name: "Other cash", currency: "USD", balance: 0,
      accountable: Depository.new, status: "active"
    )
    payment = create_payment
    payment.update!(account: other_account)
    create_entry(name: "Monthly bill", amount: 100)

    assert_equal 100, account_forecast.historical_monthly_savings.amount
    assert_equal 100, wealth_forecast.historical_monthly_savings.amount
  end

  test "disabling Agenda in wealth includes the unexplained historical cashflow" do
    create_payment
    create_entry(name: "Monthly bill", amount: 100)

    forecast = ScheduledPayment::WealthForecast.new(family: @family, user: @user, include_agenda: false)

    assert_equal 100, forecast.historical_monthly_savings.amount
    assert_equal 0, forecast.cashflow_diagnostics[:months].last.agenda_removed
  end

  test "explicit links remove irregular movements from both reserves even with different descriptions" do
    payment = create_payment
    entry = create_entry(name: "Unrelated bank title", amount: 1_200)
    entry.entryable.update!(forecast_behavior: "irregular_recurring")
    payment.scheduled_payment_entries.create!(entry: entry, scheduled_date: @date, status: "confirmed")

    assert_equal 0, account_forecast.irregular_reserve.amount
    assert_equal 0, wealth_forecast.irregular_reserve.amount
    assert_equal 200, account_forecast.historical_monthly_savings.amount
    assert_equal 200, wealth_forecast.historical_monthly_savings.amount
  end

  test "confirmed scheduled transfer explains both linked legs regardless of heuristic" do
    destination = @family.accounts.create!(owner: @user, name: "Destination", currency: "USD", balance: 0, accountable: Depository.new)
    payment = create_payment
    payment.update!(payment_type: "transfer", target_account: destination)
    outflow = create_entry(name: "Cash sent", amount: 100)
    inflow = destination.entries.create!(date: @date, name: "Cash received", amount: -100, currency: "USD", entryable: Transaction.new(forecast_behavior: "irregular_recurring"))
    payment.scheduled_payment_entries.create!(entry: outflow, transfer_entry: inflow, scheduled_date: @date, status: "confirmed")

    forecast = ScheduledPayment::Forecast.new(family: @family, user: @user, account: destination)
    assert_equal 0, forecast.irregular_reserve.amount
    assert_equal 200, wealth_forecast.historical_monthly_savings.amount
  end

  private

    def account_forecast
      ScheduledPayment::Forecast.new(family: @family, user: @user, account: @account)
    end

    def wealth_forecast
      ScheduledPayment::WealthForecast.new(family: @family, user: @user)
    end

    def create_payment
      @family.scheduled_payments.create!(
        account: @account, title: "Monthly bill", amount: 100, currency: "USD",
        frequency: "once", payment_type: "expense", start_date: @date,
        next_run_date: @date, status: "completed"
      )
    end

    def create_entry(name:, amount:, currency: "USD")
      @account.entries.create!(date: @date, name: name, amount: amount, currency: currency, entryable: Transaction.new)
    end
end
