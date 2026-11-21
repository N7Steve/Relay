require "test_helper"

class Settings::PreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "get" do
    get settings_preferences_url

    assert_response :success
  end

  test "group moniker uses group currencies copy and hides legacy currency field" do
    users(:family_admin).family.update!(moniker: "Group")

    get settings_preferences_url

    assert_response :success
    assert_includes response.body, "Group Currencies"
    assert_includes response.body, "your group"
    assert_select "select[name='user[family_attributes][currency]']", count: 0
  end

  test "renders preview features toggle for non-admin users too" do
    sign_in users(:family_member)
    get settings_preferences_url

    assert_response :success
    assert_includes response.body, "Enable preview features"
  end

  test "update toggles preview_features_enabled on" do
    user = users(:family_admin)
    assert_not user.preview_features_enabled?

    patch settings_preferences_url, params: { user: { preview_features_enabled: "1" } }

    assert_redirected_to settings_preferences_url
    assert user.reload.preview_features_enabled?
  end

  test "update toggles preview_features_enabled off" do
    user = users(:family_admin)
    user.update!(preferences: (user.preferences || {}).merge("preview_features_enabled" => true))
    assert user.preview_features_enabled?

    patch settings_preferences_url, params: { user: { preview_features_enabled: "0" } }

    assert_redirected_to settings_preferences_url
    assert_not user.reload.preview_features_enabled?
  end

  test "members can save and clear their own custom MCP instructions" do
    admin = users(:family_admin)
    admin.update!(mcp_custom_instructions: "Keep the admin's instructions")
    member = users(:family_member)
    sign_in member
    instructions = "Consulta la cuenta conjunta.\nAclara transferencias ambiguas."

    patch settings_preferences_url, params: { user: { id: admin.id, mcp_custom_instructions: instructions } }

    assert_redirected_to settings_preferences_url
    assert_equal instructions, member.reload.mcp_custom_instructions
    assert_equal "Keep the admin's instructions", admin.reload.mcp_custom_instructions
    follow_redirect!
    assert_select "textarea[name='user[mcp_custom_instructions]']", text: instructions

    patch settings_preferences_url, params: { user: { preview_features_enabled: "1" } }
    assert_equal instructions, member.reload.mcp_custom_instructions

    patch settings_preferences_url, params: { user: { mcp_custom_instructions: " \n " } }
    assert_redirected_to settings_preferences_url
    assert_nil member.reload.mcp_custom_instructions
    assert member.preview_features_enabled?
  end

  test "rejects oversized MCP instructions and keeps the saved instructions" do
    user = users(:family_admin)
    user.update!(mcp_custom_instructions: "Saved")
    too_long = "a" * (User::MCP_CUSTOM_INSTRUCTIONS_MAX_LENGTH + 1)

    patch settings_preferences_url, params: { user: { mcp_custom_instructions: too_long } }

    assert_response :unprocessable_entity
    assert_select "textarea[name='user[mcp_custom_instructions]']", text: too_long
    assert_equal "Saved", user.reload.mcp_custom_instructions
  end

  test "household budget toggle and sharing card only render once personal_budgets is on" do
    user = users(:family_admin)
    user.update!(preferences: (user.preferences || {}).merge("preview_features_enabled" => true))

    get settings_preferences_url
    assert_response :success
    assert_not_includes response.body, I18n.t("settings.preferences.show.household_budget_enabled")
    assert_not_includes response.body, I18n.t("settings.preferences.show.budget_sharing_title")

    user.family.update!(personal_budgets: true)

    get settings_preferences_url
    assert_response :success
    assert_includes response.body, I18n.t("settings.preferences.show.household_budget_enabled")
    assert_includes response.body, I18n.t("settings.preferences.show.budget_sharing_title")
  end

  test "hides the sharing card when personal_budgets is on but preview features are off" do
    user = users(:family_admin)
    user.family.update!(personal_budgets: true)
    assert_not user.preview_features_enabled?

    get settings_preferences_url

    assert_response :success
    assert_not_includes response.body, I18n.t("settings.preferences.show.household_budget_enabled")
    assert_not_includes response.body, I18n.t("settings.preferences.show.budget_sharing_title")
  end
end
