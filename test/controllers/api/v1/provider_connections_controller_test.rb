# frozen_string_literal: true

require "test_helper"

class Api::V1::ProviderConnectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @enable_banking_item = enable_banking_items(:one)

    @user.api_keys.active.destroy_all

    @api_key = ApiKey.create!(
      user: @user,
      name: "Test Read Key",
      scopes: [ "read" ],
      display_key: "test_read_#{SecureRandom.hex(8)}",
      source: "web"
    )

    @read_write_key = ApiKey.create!(
      user: @user,
      name: "Test Read-Write Key",
      scopes: [ "read_write" ],
      display_key: "test_rw_#{SecureRandom.hex(8)}",
      source: "mobile"
    )

    redis = Redis.new
    redis.del("api_rate_limit:#{@api_key.id}")
    redis.del("api_rate_limit:#{@read_write_key.id}")
  end

  test "only retained connections are exposed for either read scope" do
    [ @api_key, @read_write_key ].each do |key|
      get api_v1_provider_connections_url, headers: api_headers(key)
      assert_response :success
      providers = JSON.parse(response.body)["data"].map { |row| row["provider"] }
      assert_includes providers, "enable_banking"
      assert_empty providers & RetiredAccountConnector::PREFIXES.map(&:underscore)
      assert_equal [ "enable_banking" ], providers.uniq
    end
  end

  test "lists provider connection status for current family" do
    failed_sync = @enable_banking_item.syncs.create!(
      status: "failed",
      failed_at: Time.current,
      error: "secret token failed"
    )

    get api_v1_provider_connections_url, headers: api_headers(@api_key)
    assert_response :success

    json_response = JSON.parse(response.body)
    enable_banking_connection = json_response["data"].detect do |connection|
      connection["id"] == @enable_banking_item.id && connection["provider"] == "enable_banking"
    end

    assert_not_nil enable_banking_connection
    assert_equal "enable_banking", enable_banking_connection["provider"]
    assert_equal "EnableBankingItem", enable_banking_connection["provider_type"]
    assert_equal @enable_banking_item.name, enable_banking_connection["name"]
    assert_equal @enable_banking_item.status, enable_banking_connection["status"]
    assert_includes [ true, false ], enable_banking_connection["requires_update"]
    assert_equal true, enable_banking_connection["credentials_configured"]
    assert_includes [ true, false ], enable_banking_connection["scheduled_for_deletion"]
    assert_includes [ true, false ], enable_banking_connection["pending_account_setup"]
    assert_equal @enable_banking_item.enable_banking_accounts.count, enable_banking_connection["accounts"]["total_count"]
    assert_equal failed_sync.id, enable_banking_connection["sync"]["latest"]["id"]
    assert_equal true, enable_banking_connection["sync"]["latest"]["error"]["present"]
    assert_equal "Sync failed", enable_banking_connection["sync"]["latest"]["error"]["message"]
  end

  test "reports failed sync errors as present without exposing raw messages" do
    failed_sync = @enable_banking_item.syncs.create!(
      status: "failed",
      failed_at: Time.current,
      error: nil
    )

    get api_v1_provider_connections_url, headers: api_headers(@api_key)
    assert_response :success

    enable_banking_connection = JSON.parse(response.body)["data"].detect do |connection|
      connection["id"] == @enable_banking_item.id && connection["provider"] == "enable_banking"
    end

    assert_equal failed_sync.id, enable_banking_connection["sync"]["latest"]["id"]
    assert_equal true, enable_banking_connection["sync"]["latest"]["error"]["present"]
    assert_equal "Sync failed", enable_banking_connection["sync"]["latest"]["error"]["message"]
  end

  test "reports stale sync errors as present" do
    stale_sync = @enable_banking_item.syncs.create!(
      status: "stale",
      syncing_at: 2.days.ago
    )

    get api_v1_provider_connections_url, headers: api_headers(@api_key)
    assert_response :success

    enable_banking_connection = JSON.parse(response.body)["data"].detect do |connection|
      connection["id"] == @enable_banking_item.id && connection["provider"] == "enable_banking"
    end

    assert_equal stale_sync.id, enable_banking_connection["sync"]["latest"]["id"]
    assert_equal true, enable_banking_connection["sync"]["latest"]["error"]["present"]
    assert_equal "Sync became stale before completion", enable_banking_connection["sync"]["latest"]["error"]["message"]
  end

  test "does not expose provider secrets or raw sync errors" do
    @enable_banking_item.syncs.create!(status: "failed", error: "private failure")
    get api_v1_provider_connections_url, headers: api_headers(@api_key)
    assert_response :success
    refute_includes response.body, @enable_banking_item.client_certificate
    refute_includes response.body, @enable_banking_item.session_id
    refute_includes response.body, "private failure"
  end
  test "fails closed when credentials are not configured" do
    EnableBankingItem.any_instance.stubs(:credentials_configured?).returns(false)
    get api_v1_provider_connections_url, headers: api_headers(@api_key)
    assert_response :success
    connection = JSON.parse(response.body)["data"].find { |row| row["provider"] == "enable_banking" }
    assert_not connection["credentials_configured"]
  end
  test "excludes another family's provider connections" do
    other_item = EnableBankingItem.create!(family: families(:empty), name: "Other family", country_code: "ES", application_id: "test-app", client_certificate: "test-cert")

    get api_v1_provider_connections_url, headers: api_headers(@api_key)
    assert_response :success

    ids = JSON.parse(response.body)["data"].map { |connection| connection["id"] }
    assert_not_includes ids, other_item.id
  end

  test "read_write key can list provider connection status" do
    get api_v1_provider_connections_url, headers: api_headers(@read_write_key)
    assert_response :success
  end


  test "returns an empty list when no provider connections exist" do
    ProviderConnectionStatus.stub(:for_family, []) do
      get api_v1_provider_connections_url, headers: api_headers(@api_key)
    end

    assert_response :success
    assert_equal [], JSON.parse(response.body)["data"]
  end

  test "requires authentication" do
    get api_v1_provider_connections_url
    assert_response :unauthorized
  end

  test "rejects api keys without read scope" do
    write_only_key = ApiKey.new(
      user: @user,
      name: "Test Write Key",
      scopes: [ "write" ],
      display_key: "test_write_#{SecureRandom.hex(8)}",
      source: "monitoring"
    ).tap { |api_key| api_key.save!(validate: false) }

    get api_v1_provider_connections_url, headers: api_headers(write_only_key)
    assert_response :forbidden
  end

  test "does not leak internal provider status errors" do
    ProviderConnectionStatus.stub(:for_family, ->(_family) { raise StandardError, "secret provider failure" }) do
      get api_v1_provider_connections_url, headers: api_headers(@api_key)
    end

    assert_response :internal_server_error
    assert_equal "internal_server_error", JSON.parse(response.body)["error"]
    refute_includes response.body, "secret provider failure"
  end

  private

    def api_headers(api_key)
      { "X-Api-Key" => api_key.plain_key }
    end
end
