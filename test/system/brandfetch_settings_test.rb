require "application_system_test_case"

class BrandfetchSettingsTest < ApplicationSystemTestCase
  test "administrator toggles Brandfetch without editing environment variables" do
    Provider::Github.any_instance.stubs(:fetch_latest_release_notes).returns(nil)
    Provider::Github.any_instance.stubs(:fetch_release_notes).returns(nil)
    Setting.unstub(:external_logos_enabled)
    Setting.external_logos_enabled = false
    sign_in users(:family_admin)

    visit settings_hosting_path
    assert_no_selector "input[name='setting[openai_model]']", visible: :all
    find("label[for='setting_external_logos_enabled']", match: :first).click
    assert_selector "input[type='checkbox'][name='setting[external_logos_enabled]'][checked]", visible: :all
    assert ExternalAccess.enabled?(:logos)
    find("label[for='setting_external_logos_enabled']", match: :first).click
    assert_selector "input[type='checkbox'][name='setting[external_logos_enabled]']:not([checked])", visible: :all
    assert_not ExternalAccess.enabled?(:logos)
    page.save_screenshot(Rails.root.join("tmp/screenshots/phase6-hosting.png"))
  end
end
