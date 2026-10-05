require "test_helper"
require_relative "../../support/historical_financekit_helper"

class Settings::ProvidersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include HistoricalFinancekitHelper

  setup do
    ensure_tailwind_build
    sign_in users(:family_admin)

    # Ensure provider adapters are loaded for all tests
    Provider::Factory.ensure_adapters_loaded
  end

  test "Apple Wallet is neither offered nor shown for historical connections" do
    create_historical_financekit_link

    get settings_providers_url

    assert_response :success
    assert_select "[data-provider-name='apple wallet']", count: 0
    assert_select "details#financekit-connection", count: 0
    assert_select "button[disabled]", text: "App Store", count: 0
    assert_equal [ "enable_banking" ], @controller.view_assigns.values_at("connected", "needs_attention", "available")
      .flatten.map { |entry| entry[:provider_key] }
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
