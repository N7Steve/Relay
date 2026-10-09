require "test_helper"

class ScheduledPayment::ForecastExplanationTest < ActiveSupport::TestCase
  setup do
    @date = Date.new(2026, 8, 10)
    @payment = ScheduledPayment.new(
      title: "Monthly bill", amount: 100, currency: "USD",
      frequency: "once", payment_type: "expense", start_date: @date
    )
    @entry = Entry.new(name: "Monthly bill", amount: 100, currency: "USD", date: @date)
  end

  test "normalizes title whitespace and case while preserving cash direction" do
    @entry.name = "  MONTHLY   bill  "
    assert @payment.explains_forecast_entry?(@entry)

    @entry.name = "Another bill"
    assert_not @payment.explains_forecast_entry?(@entry)

    @entry.name = @payment.title
    @entry.amount = -100
    assert_not @payment.explains_forecast_entry?(@entry)

    @payment.payment_type = "income"
    assert @payment.explains_forecast_entry?(@entry)
  end

  test "fixed amount tolerance includes both ten percent boundaries" do
    [ 90, 110 ].each do |amount|
      @entry.amount = amount
      assert @payment.explains_forecast_entry?(@entry)
    end
    [ BigDecimal("89.99"), BigDecimal("110.01") ].each do |amount|
      @entry.amount = amount
      assert_not @payment.explains_forecast_entry?(@entry)
    end
  end

  test "estimated amount tolerance remains thirty five percent" do
    @payment.amount_estimated = true
    [ 65, 135 ].each do |amount|
      @entry.amount = amount
      assert @payment.explains_forecast_entry?(@entry)
    end
    [ BigDecimal("64.99"), BigDecimal("135.01") ].each do |amount|
      @entry.amount = amount
      assert_not @payment.explains_forecast_entry?(@entry)
    end
  end

  test "requires a scheduled occurrence within five days in either direction" do
    [ -5, 5 ].each do |offset|
      @entry.date = @date + offset.days
      assert @payment.explains_forecast_entry?(@entry)
    end
    [ -6, 6 ].each do |offset|
      @entry.date = @date + offset.days
      assert_not @payment.explains_forecast_entry?(@entry)
    end
  end

  test "recurring occurrences respect the schedule end date regardless of status" do
    @payment.frequency = "monthly"
    @payment.frequency_day = @date.day
    @payment.end_date = @date.next_month
    @entry.date = @date.next_month
    @payment.status = "completed"
    assert @payment.explains_forecast_entry?(@entry)

    @entry.date = @date.next_month(2)
    assert_not @payment.explains_forecast_entry?(@entry)
  end

  test "same currency is always required" do
    @entry.currency = "EUR"
    assert_not @payment.explains_forecast_entry?(@entry)
  end
end
