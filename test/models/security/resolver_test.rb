require "test_helper"

class Security::ResolverTest < ActiveSupport::TestCase
  test "resolves DB security" do
    db_security = Security.create!(ticker: "TSLA", exchange_operating_mic: "XNAS", country_code: "US")

    resolved = Security::Resolver.new("TSLA", exchange_operating_mic: "XNAS", country_code: "US").resolve

    assert_equal db_security, resolved
  end

  test "resolves an unknown ticker as an offline security" do
    assert_difference "Security.count", 1 do
      resolved = Security::Resolver.new("FOO", exchange_operating_mic: "XNAS", country_code: "US").resolve

      assert resolved.persisted?, "Offline security should be saved"
      assert_equal "FOO", resolved.ticker
      assert_equal "XNAS", resolved.exchange_operating_mic
      assert_equal "US", resolved.country_code
      assert resolved.offline, "Offline securities should be flagged offline"
    end
  end

  test "keeps the stored price provider of a historical security" do
    db_security = Security.create!(ticker: "CSPX", exchange_operating_mic: "XLON", country_code: "GB")
    db_security.update_columns(price_provider: "tiingo")

    resolved = Security::Resolver.new("CSPX", exchange_operating_mic: "XLON", country_code: "GB").resolve

    assert_equal db_security, resolved
    assert_equal "tiingo", resolved.reload.price_provider
  end

  test "returns nil when symbol blank" do
    assert_raises(ArgumentError) { Security::Resolver.new(nil).resolve }
    assert_raises(ArgumentError) { Security::Resolver.new("").resolve }
  end

  test "canonicalizes legacy WAR MIC to XWAR on resolve and reuses existing row" do
    legacy = Security.create!(ticker: "KTY", exchange_operating_mic: "XWAR", country_code: "PL")
    legacy.update_columns(exchange_operating_mic: "WAR")

    resolved = Security::Resolver.new("KTY", exchange_operating_mic: "WAR", country_code: "PL").resolve

    assert_equal legacy.id, resolved.id
    assert_equal "XWAR", resolved.reload.exchange_operating_mic
  end

  test "WAR and XWAR resolve to the same security without creating a duplicate" do
    assert_difference "Security.count", 1 do
      resolved = Security::Resolver.new("KTY", exchange_operating_mic: "WAR", country_code: "PL").resolve
      assert_equal "XWAR", resolved.exchange_operating_mic
    end

    assert_no_difference "Security.count" do
      again = Security::Resolver.new("KTY", exchange_operating_mic: "XWAR", country_code: "PL").resolve
      assert_equal "XWAR", again.exchange_operating_mic
    end
  end

  test "prefers canonical XWAR when both WAR and XWAR rows exist" do
    canonical = Security.create!(ticker: "KTY", exchange_operating_mic: "XWAR", country_code: "PL")
    legacy = Security.new(ticker: "KTY", exchange_operating_mic: "WAR", country_code: "PL")
    legacy.save!(validate: false)

    resolved = Security::Resolver.new("KTY", exchange_operating_mic: "WAR", country_code: "PL").resolve

    assert_equal canonical.id, resolved.id
    assert_equal "XWAR", resolved.exchange_operating_mic
  end
end
