require "test_helper"

class ExternalAccessControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  setup do
    ExternalAccess::CAPABILITIES.each { |capability| Setting.stubs("external_#{capability}_enabled").returns(false) }
    Setting.stubs(:ai_features_enabled?).returns(false)
    sign_in users(:family_admin)
  end

  test "manual finance pages remain available with all external capabilities disabled" do
    ExternalAccess::CAPABILITIES.each { |capability| Setting.stubs("external_#{capability}_enabled").returns(false) }
    get accounts_path
    assert_response :success
    assert_select "body[data-bank-sync-enabled=false]"
    assert_select "img[src*='cdn.brandfetch.io']", count: 0
  end

  test "connector actions are forbidden before creating a connection" do
    Setting.stubs(:external_bank_sync_enabled).returns(false)
    assert_no_difference "SimplefinItem.count" do
      post simplefin_items_path, params: { simplefin_item: { name: "Disabled", access_url: "https://example.com" } }
    end
    assert_response :forbidden
  end

  test "the authenticated accounts API remains available without external capabilities" do
    ExternalAccess::CAPABILITIES.each { |capability| Setting.stubs("external_#{capability}_enabled").returns(false) }
    user = users(:family_admin)
    user.api_keys.active.destroy_all
    key = ApiKey.create!(user: user, name: "Local read", scopes: [ "read" ],
      source: "web", display_key: "local_#{SecureRandom.hex(8)}")
    get "/api/v1/accounts", headers: { "X-Api-Key" => key.display_key }
    assert_response :success
  end

  test "manual refresh recalculates a linked account while its connector is suspended" do
    Setting.stubs(:external_bank_sync_enabled).returns(false)
    account = accounts(:depository)
    Account.any_instance.stubs(:linked?).returns(true)
    assert_enqueued_jobs 1, only: SyncJob do
      post sync_account_path(account)
    end
    assert_equal "Account", account.syncs.ordered.first.syncable_type
  end

  test "sidebar warns about missing FX and preserves navigation to manual input" do
    users(:family_admin).family.update!(currency: "EUR")
    ExchangeRate.where(to_currency: "EUR").delete_all
    Setting.stubs(:external_market_data_enabled).returns(false)
    get new_depository_path
    assert_response :success
    assert_match I18n.t("external_access.insufficient_data", details: "").strip, response.body
  end
end
