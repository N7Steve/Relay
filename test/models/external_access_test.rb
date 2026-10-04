require "test_helper"

class ExternalAccessTest < ActiveSupport::TestCase
  test "new settings require explicit activation independently of credentials" do
    ExternalAccess::CAPABILITIES.each do |capability|
      Setting.unstub("external_#{capability}_enabled")
      assert_not ExternalAccess.enabled?(capability)
    end
  end

  test "local recalculation cannot fetch market data even when enabled" do
    assert ExternalAccess.enabled?(:market_data)
    ExternalAccess.locally do
      assert_nil ExchangeRate.provider
      assert_empty Security.providers
      assert_raises(ExternalAccess::Disabled) { ExternalAccess.require!(:market_data) }
    end
    assert ExternalAccess.enabled?(:market_data)
  end

  test "local execution state is restored after an error" do
    assert_raises(RuntimeError) { ExternalAccess.locally { raise "failed" } }
    assert_not ExternalAccess.local_recalculation?
  end

  test "an explicit environment choice overrides a persisted preference" do
    variable = "RELAY_EXTERNAL_BANK_SYNC_ENABLED"
    previous = ENV[variable]
    ENV[variable] = "false"
    assert_not ExternalAccess.enabled?(:bank_sync)
    ENV[variable] = "true"
    Setting.stubs(:external_bank_sync_enabled).returns(false)
    assert ExternalAccess.enabled?(:bank_sync)
  ensure
    ENV[variable] = previous
  end

  test "a previously constructed Enable Banking client is blocked after suspension" do
    provider = Provider::EnableBanking.new(application_id: "test", client_certificate: OpenSSL::PKey::RSA.new(2048).to_pem)
    Setting.stubs(:external_bank_sync_enabled).returns(false)
    assert_raises(ExternalAccess::Disabled) { provider.get_session(session_id: "session") }
  end

  test "disabling banks prevents a direct client request before transport" do
    Setting.stubs(:external_bank_sync_enabled).returns(false)
    assert_raises(ExternalAccess::Disabled) { Provider::EnableBanking.get("/accounts") }
  end

  test "disabling market data prevents requests from an existing connection" do
    connection = Faraday.new do |faraday|
      faraday.use ExternalAccess::RequestMiddleware, :market_data
      faraday.adapter :test do |stub|
        stub.get("/prices") { flunk "Transport must not execute" }
      end
    end
    Setting.stubs(:external_market_data_enabled).returns(false)
    assert_raises(ExternalAccess::Disabled) { connection.get("/prices") }
  end

  test "missing FX raises instead of valuing foreign currency at one" do
    Setting.stubs(:external_market_data_enabled).returns(false)
    ExchangeRate.where(from_currency: "JPY", to_currency: "CHF").delete_all
    rates = ExchangeRate.rates_for([ "JPY" ], to: "CHF")
    assert_equal 1, rates["CHF"]
    assert_raises(Money::ConversionError) { rates["JPY"] }
  end

  test "logos and drive remain independently activatable" do
    Setting.stubs(:external_bank_sync_enabled).returns(false)
    Setting.stubs(:brand_fetch_client_id).returns("test-client")
    assert_includes Setting.brand_fetch_icon_url("example.com"), "cdn.brandfetch.io"
    Setting.stubs(:external_logos_enabled).returns(false)
    assert_nil Setting.brand_fetch_icon_url("example.com")
    assert_nil Setting.transform_brand_fetch_url("https://cdn.brandfetch.io/example.com/icon.png")
    assert ExternalAccess.enabled?(:google_drive)
  end
end
