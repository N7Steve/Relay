require "test_helper"

class RetiredMarketDataTest < ActiveSupport::TestCase
  test "market and exchange rate providers are gone from the runtime" do
    %w[Provider::TwelveData Provider::YahooFinance Provider::Tiingo Provider::Eodhd Provider::AlphaVantage
       Provider::Mansa Provider::Mfapi Provider::BinancePublic Provider::MoexPublic Provider::Frankfurter
       Provider::TinkoffInvest Provider::SecurityConcept Provider::ExchangeRateConcept MarketDataImporter
       Account::MarketDataImporter Security::Provided Security::HealthChecker Security::Price::Importer
       ExchangeRate::Importer SecuritiesController].each do |name|
      assert_nil name.safe_constantize, "#{name} should be retired"
    end
    assert_equal %i[property_valuations], Provider::Registry::CONCEPTS
  end

  test "retired market data jobs are gone from the runtime" do
    %w[ImportMarketDataJob SecurityHealthCheckJob YahooFinanceHealthCheckJob].each do |name|
      assert_nil name.safe_constantize, "#{name} should be retired"
    end
  end

  test "price and rate lookups never create market data" do
    security = securities(:aapl)
    security.prices.where(date: Date.current).delete_all
    ExchangeRate.where(from_currency: "USD", to_currency: "NOK").delete_all

    assert_no_difference [ "Security::Price.count", "ExchangeRate.count" ] do
      assert_nil security.current_price
      assert_nil ExchangeRate.find_rate(from: "USD", to: "NOK")
      assert_raises(Money::ConversionError) { Money.new(10, "USD").exchange_to("NOK") }
    end
  end
end
