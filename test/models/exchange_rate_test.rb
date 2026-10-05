require "test_helper"

class ExchangeRateTest < ActiveSupport::TestCase
  test "finds rate in DB" do
    existing_rate = exchange_rates(:one)

    assert_equal existing_rate, ExchangeRate.find_rate(
                                              from: existing_rate.from_currency,
                                              to: existing_rate.to_currency,
                                              date: existing_rate.date
                                            )
  end

  test "returns nil without a stored rate and never creates one" do
    ExchangeRate.delete_all

    assert_no_difference "ExchangeRate.count" do
      assert_nil ExchangeRate.find_rate(from: "USD", to: "EUR", date: Date.current)
    end
  end

  test "reuses nearest stored rate within lookback window" do
    friday = 1.day.ago.to_date
    ExchangeRate.create!(from_currency: "USD", to_currency: "JPY", date: friday, rate: 150.5)

    result = ExchangeRate.find_rate(from: "USD", to: "JPY", date: Date.current)

    assert_equal 150.5, result.rate
    assert_equal friday, result.date
  end

  test "does not reuse stored rate outside lookback window" do
    ExchangeRate.where(from_currency: "USD", to_currency: "JPY").delete_all
    old_date = (ExchangeRate::NEAREST_RATE_LOOKBACK_DAYS + 1).days.ago.to_date
    ExchangeRate.create!(from_currency: "USD", to_currency: "JPY", date: old_date, rate: 140.0)

    assert_nil ExchangeRate.find_rate(from: "USD", to: "JPY", date: Date.current)
  end

  test "batch rates use stored rates and raise for missing currencies" do
    ExchangeRate.where(to_currency: "CHF").delete_all
    ExchangeRate.create!(from_currency: "EUR", to_currency: "CHF", date: 2.days.ago.to_date, rate: 0.95)

    rates = ExchangeRate.rates_for(%w[EUR JPY], to: "CHF")

    assert_equal 0.95, rates["EUR"]
    assert_equal 1, rates["CHF"]
    assert_raises(Money::ConversionError) { rates["JPY"] }
  end
end
