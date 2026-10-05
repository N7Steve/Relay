require "test_helper"
require "ostruct"

class Settings::HostingsControllerTest < ActionDispatch::IntegrationTest
  include ProviderTestHelper

  setup do
    sign_in users(:family_admin)

    @provider = mock
    Provider::Registry.stubs(:get_provider).with(:rentcast).returns(@provider)
    Provider::Registry.stubs(:get_provider).with(:realie).returns(nil)
    @usage_response = provider_success_response(
      OpenStruct.new(
        used: 10,
        limit: 100,
        utilization: 10,
        plan: "free",
      )
    )
    @provider.stubs(:usage).returns(@usage_response)
  end

  test "Brandfetch can be enabled and disabled even with a legacy environment override" do
    Setting.unstub(:external_logos_enabled)
    ClimateControl.modify("RELAY_EXTERNAL_LOGOS_ENABLED" => "false") do
      patch settings_hosting_url, params: { setting: { external_logos_enabled: "1", brand_fetch_client_id: "test-client" } }
      assert_redirected_to settings_hosting_url
      assert ExternalAccess.enabled?(:logos)
      assert_includes Setting.brand_fetch_icon_url("example.com"), "cdn.brandfetch.io"
      get settings_hosting_url
      assert_select "input[name='setting[external_logos_enabled]'][type='checkbox'][checked]"

      patch settings_hosting_url, params: { setting: { external_logos_enabled: "0" } }
      assert_not ExternalAccess.enabled?(:logos)
      assert_nil Setting.brand_fetch_icon_url("example.com")
      assert_nil Setting.transform_brand_fetch_url("https://cdn.brandfetch.io/example.com/icon.png")
    end
  end

  test "Brandfetch instance choice also overrides an enabled legacy environment" do
    Setting.unstub(:external_logos_enabled)
    ClimateControl.modify("RELAY_EXTERNAL_LOGOS_ENABLED" => "true") do
      patch settings_hosting_url, params: { setting: { external_logos_enabled: "0" } }
      assert_not ExternalAccess.enabled?(:logos)
    end
  end

  test "members cannot change the Brandfetch instance preference" do
    sign_in users(:family_member)
    assert_no_difference -> { Setting.where(var: "external_logos_enabled").count } do
      patch settings_hosting_url, params: { setting: { external_logos_enabled: "1" } }
    end
    assert_redirected_to settings_hosting_url
  end

  test "should get edit when self hosting is enabled" do
    @provider.expects(:usage).returns(@usage_response)

    with_self_hosting do
      get settings_hosting_url
      assert_response :success
    end
  end

  test "external services settings render as collapsible cards" do
    with_self_hosting do
      get settings_hosting_url(locale: :es)

      assert_response :success
      assert_includes response.body, "Configuración de instancia"
      assert_select "details > summary h2", text: I18n.t("settings.hostings.show.general", locale: :es)
      assert_select "details > summary h2", text: I18n.t("settings.hostings.show.property_valuation_providers", locale: :es)
      assert_select "details > summary h2", text: I18n.t("settings.hostings.show.sync_settings", locale: :es)
      assert_select "details:not([open]) > summary h2", text: I18n.t("settings.hostings.show.danger_zone", locale: :es)
    end
  end

  test "only a super admin can opt in and the selected family must own the demo email" do
    # The configured demo email is already used by the new_email fixture.
    demo_email = "disposable-demo@example.com"
    Rails.application.stubs(:config_for).with(:demo).returns({ email: demo_email })

    with_self_hosting do
      patch settings_hosting_url, params: { setting: { demo_family_refresh_enabled: "1" } }
      assert_not Setting.demo_family_refresh_enabled

      sign_in users(:sure_support_staff)
      patch settings_hosting_url, params: { setting: { demo_family_refresh_enabled: "1" } }
      assert_response :unprocessable_entity
      assert_not Setting.demo_family_refresh_enabled

      family = families(:dylan_family)
      patch settings_hosting_url, params: { setting: { demo_family_refresh_family_id: family.id } }
      assert_response :unprocessable_entity

      demo_family = Family.create!(name: "Disposable Demo")
      demo_family.users.create!(first_name: "Demo", last_name: "Owner", email: demo_email, password: "password123", role: :admin)
      patch settings_hosting_url, params: { setting: { demo_family_refresh_family_id: demo_family.id } }
      assert_redirected_to settings_hosting_path
      patch settings_hosting_url, params: { setting: { demo_family_refresh_enabled: "1" } }
      assert Setting.demo_family_refresh_enabled
    end
  end

  test "demo family selection excludes non-admin email owners and cannot be cleared while enabled" do
    demo_email = "demo-selection@example.com"
    Rails.application.stubs(:config_for).with(:demo).returns({ email: demo_email })
    demo_family = Family.create!(name: "Demo Selection")
    demo_user = demo_family.users.create!(first_name: "Demo", last_name: "Member", email: demo_email, password: "password123", role: :member)
    sign_in users(:sure_support_staff)

    with_self_hosting do
      get settings_hosting_url
      assert_response :success
      assert_select "option[value='#{demo_family.id}']", count: 0

      patch settings_hosting_url, params: { setting: { demo_family_refresh_family_id: demo_family.id } }
      assert_response :unprocessable_entity
      assert_nil Setting.demo_family_refresh_family_id

      demo_user.update!(role: :super_admin)
      get settings_hosting_url
      assert_select "option[value='#{demo_family.id}']", count: 0
      demo_user.update!(role: :admin)
      other_admin = demo_family.users.create!(first_name: "Instance", last_name: "Admin", email: "instance-admin@example.com", password: "password123", role: :super_admin)
      get settings_hosting_url
      assert_select "option[value='#{demo_family.id}']", count: 0
      other_admin.update!(role: :member)
      get settings_hosting_url
      assert_select "option[value='#{demo_family.id}']", count: 1
      patch settings_hosting_url, params: { setting: { demo_family_refresh_family_id: demo_family.id } }
      assert_redirected_to settings_hosting_path
      patch settings_hosting_url, params: { setting: { demo_family_refresh_enabled: "1" } }
      assert Setting.demo_family_refresh_enabled

      patch settings_hosting_url, params: { setting: { demo_family_refresh_family_id: "" } }
      assert_response :unprocessable_entity
      assert_equal demo_family.id.to_s, Setting.demo_family_refresh_family_id
      assert Setting.demo_family_refresh_enabled

      patch settings_hosting_url, params: { setting: { demo_family_refresh_family_id: "", demo_family_refresh_enabled: "0" } }
      assert_redirected_to settings_hosting_path
      assert_nil Setting.demo_family_refresh_family_id
      assert_not Setting.demo_family_refresh_enabled
    end
  end

  test "can update rentcast api key when self hosting is enabled" do
    with_self_hosting do
      patch settings_hosting_url, params: { setting: { rentcast_api_key: "rentcast-token" } }

      assert_equal "rentcast-token", Setting.rentcast_api_key
    end
  end

  test "can update realie api key when self hosting is enabled" do
    with_self_hosting do
      patch settings_hosting_url, params: { setting: { realie_api_key: "realie-token" } }

      assert_equal "realie-token", Setting.realie_api_key
    end
  end

  test "market data providers are not configurable" do
    with_self_hosting do
      get settings_hosting_url

      assert_response :success
      %w[setting[exchange_rate_provider] setting[securities_providers][] setting[twelve_data_api_key]
         setting[tiingo_api_key] setting[eodhd_api_key] setting[alpha_vantage_api_key]
         setting[tinkoff_invest_api_key] setting[mansa_api_key]].each do |field|
        assert_select "[name='#{field}']", count: 0
      end
      assert_select "[name='setting[rentcast_api_key]']"

      patch settings_hosting_url, params: { setting: { twelve_data_api_key: "ignored", exchange_rate_provider: "yahoo_finance",
                                                       securities_providers: [ "twelve_data" ] } }

      assert_redirected_to settings_hosting_url
      assert_not Setting.where(var: %w[twelve_data_api_key exchange_rate_provider securities_providers]).exists?
      assert_not Setting.respond_to?(:twelve_data_api_key)
    end
  end

  test "can clear an encrypted api key by submitting a blank value" do
    with_self_hosting do
      patch settings_hosting_url, params: { setting: { rentcast_api_key: "1234567890" } }
      assert_equal "1234567890", Setting.rentcast_api_key

      patch settings_hosting_url, params: { setting: { rentcast_api_key: "" } }
      assert_nil Setting.rentcast_api_key
    end
  end

  test "submitting the masked placeholder leaves an encrypted api key unchanged" do
    with_self_hosting do
      patch settings_hosting_url, params: { setting: { rentcast_api_key: "1234567890" } }

      patch settings_hosting_url, params: { setting: { rentcast_api_key: "********" } }
      assert_equal "1234567890", Setting.rentcast_api_key
    end
  end

  test "can update onboarding state when self hosting is enabled" do
    sign_in users(:sure_support_staff)

    with_self_hosting do
      patch settings_hosting_url, params: { setting: { onboarding_state: "invite_only" } }

      assert_equal "invite_only", Setting.onboarding_state
      assert Setting.require_invite_for_signup

      patch settings_hosting_url, params: { setting: { onboarding_state: "closed" } }

      assert_equal "closed", Setting.onboarding_state
      refute Setting.require_invite_for_signup
    end
  end

  # Regression: issue #2465 symptom for the OpenAI token. Blanking the field
  # (the form auto-submits on blur) must clear the stored value, not silently
  # keep the old one.

  # Regression: issue #2465 symptom for the Anthropic token.

  # Regression: issue #1824. The OpenAI form auto-submits on blur, so entering
  # the URI base before the model fires a partial submit that fails validation.
  # The re-rendered form must show the user's submitted URI base — not the
  # still-blank saved value — so they can finish typing the model.

  # PR #1862 review (jjmata): symmetric coverage for the model field. When the
  # user changes the URI base and clears the model in the same auto-submit, the
  # cross-field validation fails — the re-rendered model input must reflect the
  # user's submitted (cleared) value, not silently revert to the saved model.

  test "can clear data cache when self hosting is enabled" do
    account = accounts(:investment)
    holding = account.holdings.first
    exchange_rate = exchange_rates(:one)
    security_price = holding.security.prices.first
    account_balance = account.balances.create!(date: Date.current, balance: 1000, currency: "USD")

    with_self_hosting do
      perform_enqueued_jobs(only: DataCacheClearJob) do
        delete clear_cache_settings_hosting_url
      end
    end

    assert_redirected_to settings_hosting_url
    assert_equal I18n.t("settings.hostings.clear_cache.cache_cleared"), flash[:notice]

    assert_not ExchangeRate.exists?(exchange_rate.id)
    assert_not Security::Price.exists?(security_price.id)
    assert_not Holding.exists?(holding.id)
    assert_not Balance.exists?(account_balance.id)
  end

  test "does not overwrite token with masked placeholder" do
    with_self_hosting do
      Setting.external_assistant_token = "real-secret"

      patch settings_hosting_url, params: { setting: { external_assistant_token: "********" } }

      assert_equal "real-secret", Setting.external_assistant_token
    end
  ensure
    Setting.external_assistant_token = nil
  end

  # Regression: issue #2465 symptom for the external assistant token.

  test "can clear data only when admin" do
    with_self_hosting do
      sign_in users(:family_member)

      assert_no_enqueued_jobs do
        delete clear_cache_settings_hosting_url
      end

      assert_redirected_to settings_hosting_url
      assert_equal I18n.t("settings.hostings.not_authorized"), flash[:alert]
    end
  end

  private
    def enable_preview_features!
      @user = users(:family_admin)
      @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    end
end
