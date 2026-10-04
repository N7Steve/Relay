require "test_helper"
require_relative "../../support/financekit_test_helper"

class Settings::ProvidersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include FinancekitTestHelper

  setup do
    ensure_tailwind_build
    sign_in users(:family_admin)

    # Ensure provider adapters are loaded for all tests
    Provider::Factory.ensure_adapters_loaded
  end

  test "Apple Wallet is available through a disabled App Store button" do
    get settings_providers_url

    assert_response :success
    assert_select "div[data-provider-name='apple wallet'][data-provider-region='us / uk'][data-provider-kind='bank']" do
      assert_select "button[disabled]", text: "App Store"
      assert_select "span[title='Coming soon!']"
      assert_select "a", count: 0
      assert_select "p", text: "US / UK · Bank"
    end
  end

  test "linked Wallet accounts appear with upload and import summaries" do
    financekit_setup
    @item.update!(last_accepted_at: 2.hours.ago, last_imported_at: 1.hour.ago)

    get settings_providers_url

    assert_response :success
    assert_select "[data-provider-name='apple wallet']", count: 0
    assert_select "details#financekit-connection" do
      assert_select "a[href=?]", account_path(@source.account), text: "Test Wallet"
      assert_select "span", text: "Sync active"
      assert_select "dt", text: "Last accepted by Relay"
      assert_select "dt", text: "Last imported into your family"
      assert_select "time[datetime=?]", @item.last_accepted_at.iso8601
      assert_select "time[datetime=?]", @item.last_imported_at.iso8601
      assert_select "form", count: 0
    end
    assert_select "form[action=?]", sync_provider_settings_providers_path(provider_key: "financekit"), count: 0
    assert_includes @controller.view_assigns["connected"].map { |entry| entry[:provider_key] }, "financekit"
  end

  test "Wallet repairs retain linked accounts and missing timestamps show Not yet" do
    financekit_setup
    @item.mark_repair!("test_repair")

    get settings_providers_url

    assert_response :success
    assert_select "details#financekit-connection" do
      assert_select "span", text: "Repair required — open the Relay iOS app"
      assert_select "dd", text: "Not yet", count: 2
      assert_select "a", text: "Test Wallet"
    end
    assert_includes @controller.view_assigns["needs_attention"].map { |entry| entry[:provider_key] }, "financekit"
  end

  test "revoked Wallet connections return to available providers" do
    financekit_setup
    @item.disconnect!

    get settings_providers_url

    assert_response :success
    assert_select "details#financekit-connection", count: 0
    assert_select "[data-provider-name='apple wallet'] button[disabled]", text: "App Store"
  end


  test "Wallet settings retain disabled accounts but exclude pending deletion" do
    financekit_setup
    @source.account.update!(status: "disabled")
    get settings_providers_url
    assert_response :success
    assert_select "details#financekit-connection a[href=?]", account_path(@source.account)

    @source.account.update!(status: "pending_deletion")
    get settings_providers_url
    assert_response :success
    assert_select "details#financekit-connection", count: 0
    assert_select "a[href=?]", account_path(@source.account), count: 0
    assert_select "[data-provider-name='apple wallet']"
  end

  test "Wallet summary excludes another family's connections" do
    financekit_setup(user: users(:empty))

    get settings_providers_url

    assert_response :success
    assert_select "details#financekit-connection", count: 0
    assert_select "[data-provider-name='apple wallet']"
  end

  test "Wallet summary excludes accounts the current admin cannot access" do
    financekit_setup
    @source.account.account_shares.destroy_all
    @source.account.update!(owner: users(:family_member))

    get settings_providers_url

    assert_response :success
    assert_select "details#financekit-connection", count: 0
    assert_select "[data-provider-name='apple wallet']"
  end

  test "GET /settings/bank_sync redirects permanently to /settings/providers" do
    get "/settings/bank_sync"
    assert_redirected_to "/settings/providers"
    assert_equal 301, response.status
  end


  test "should get show when self hosting is enabled" do
    with_self_hosting do
      get settings_providers_url
      assert_response :success
    end
  end

  # A panel missing from family_panel_items reports :ok forever, however badly its
  # connection is doing: compute_provider_sync_health skips any key whose items are
  # absent, so no error badge ever reaches the page.




  # Row panels used to sit in a frame of their own. A redirect to a page
  # without that frame showed "Content missing", and a stream to
  # "<key>-providers-panel" replaced the frame when the two shared that id.
  test "connection rows post from the page and leave panel ids unique" do
    get settings_providers_url

    assert_response :success
    assert_operator css_select("details[id$='-connection']").size, :>=, 1
    assert_select "details[id$='-connection'] turbo-frame", count: 0

    panel_ids = css_select("[id$='-providers-panel']").map { |element| element["id"] }
    assert_equal panel_ids.uniq, panel_ids
  end

  # Saves and errors from a row or the drawer re-render the panel by replacing
  # "<turbo_id>-providers-panel", and EnableBankingItem::SyncCompleteEvent does
  # the same when a sync finishes. SnapTrade never streams to it.


  # The provider card reads its tagline with `default: nil`, so a missing key
  # renders a bare name rather than failing. Up shipped that way.
  test "every family panel provider has an English tagline" do
    missing = Settings::ProvidersController::FAMILY_PANEL_KEYS.reject do |key|
      I18n.exists?("settings.providers.taglines.#{key}", :en)
    end

    assert_empty missing
  end

  test "sync all control submits with POST" do
    SimplefinItem.create!(
      family: families(:dylan_family),
      name: "Test SimpleFIN Sync All Control",
      access_url: "https://bridge.simplefin.org/simplefin/access"
    )

    with_self_hosting do
      get settings_providers_url
      assert_response :success
      assert_select "form[action=?][method=?]", sync_all_settings_providers_path, "post"
    end
  end














  test "POST sync_all enqueues SyncAllProvidersJob" do
    SimplefinItem.create!(
      family: families(:dylan_family),
      name: "Test SimpleFIN Sync All",
      access_url: "https://bridge.simplefin.org/simplefin/access"
    )
    families(:dylan_family).update_column(:last_sync_all_attempted_at, nil)

    assert_enqueued_with(job: SyncAllProvidersJob) do
      post sync_all_settings_providers_path
    end

    assert_redirected_to settings_providers_path

    follow_redirect!
    assert_response :success
    assert_match(/Syncing all connected providers/i, response.body)
  end

  test "POST sync_all respects recent sync throttle" do
    families(:dylan_family).update_column(:last_sync_all_attempted_at, Time.current)

    assert_no_enqueued_jobs only: SyncAllProvidersJob do
      post sync_all_settings_providers_path
    end

    assert_redirected_to settings_providers_path
    assert_equal I18n.t("settings.providers.sync_all_recently"), flash[:notice]
  end








  test "GET connect_form uses shared encryption warning for provider panels" do
    ActiveRecordEncryptionConfig.stubs(:explicitly_configured?).returns(false)

    get connect_form_settings_providers_path(provider_key: "enable_banking")

    assert_response :success
    assert_includes response.body, I18n.t("settings.providers.provider_setup_encryption_warning.title")
    assert_includes response.body, I18n.t("settings.providers.provider_setup_encryption_warning.message")
    assert_includes response.body, I18n.t("settings.providers.drawer_trust_statement_encryption_unconfigured")
    refute_includes response.body, I18n.t("settings.providers.drawer_trust_statement")
  end
end
