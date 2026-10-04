require "test_helper"

class Settings::ProviderPanelsTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:family_admin) }

  test "Enable Banking sync and disconnect actions are named DS buttons" do
    get connect_form_settings_providers_path(provider_key: "enable_banking")
    assert_response :success
    buttons = css_select("turbo-frame#enable_banking-connect-form button")
    assert buttons.any?
    buttons.each do |button|
      assert (button["aria-label"].presence || button.text.squish.presence)
      assert_includes button["class"].to_s.split, "focus-ring"
    end
    assert_select "turbo-frame#enable_banking-connect-form button[data-turbo-confirm]", minimum: 1
  end

  test "retired provider drawers are unavailable" do
    RetiredAccountConnector::PREFIXES.each do |provider_key|
      get connect_form_settings_providers_path(provider_key: provider_key.underscore)
      assert_redirected_to settings_providers_path
    end
  end
end
