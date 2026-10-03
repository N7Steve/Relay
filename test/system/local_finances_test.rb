require "application_system_test_case"

class LocalFinancesTest < ApplicationSystemTestCase
  test "a manual account can be created with all external capabilities disabled" do
    ExternalAccess::CAPABILITIES.each { |capability| Setting.stubs("external_#{capability}_enabled").returns(false) }
    Setting.stubs(:ai_features_enabled?).returns(false)
    sign_in users(:family_admin)
    visit accounts_path
    click_link I18n.t("accounts.index.new_account"), match: :first
    within "#modal dialog[open]" do
      click_link Depository.singular_display_name
    end
    click_link "Enter account balance"
    fill_in "Account name*", with: "Offline manual account"
    fill_in "account[balance]", with: 125
    click_button "Create Account"
    assert_no_selector "dialog[open]"
    visit accounts_path
    assert_text "Offline manual account"
    assert_selectors_have_no_external_images
    external_requests = page.evaluate_script(<<~JS)
      performance.getEntriesByType("resource")
        .map((entry) => entry.name)
        .filter((url) => /^https?:/.test(url) && new URL(url).origin !== location.origin)
    JS
    assert_empty external_requests
  end

  private
    def assert_selectors_have_no_external_images
      assert_no_selector "img[src*='cdn.brandfetch.io']"
      assert_no_selector "script[src*='cdn.plaid.com']", visible: :all
    end
end
