require "test_helper"

class CashFlowPreviewTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "preview opt-in adds the web chart below identical legacy chart data" do
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => false))
    get root_path
    assert_response :success
    assert_select "#cashflow-preview", count: 0
    assert_select "[data-controller='cash-flow']", count: 0
    legacy = css_select("[data-controller='sankey-chart']").map { |chart| chart["data-sankey-chart-data-value"] }
    assert_equal 2, legacy.length

    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => true))
    get root_path
    assert_response :success
    assert_select "#cashflow-sankey-chart + #cashflow-preview", count: 1
    assert_select "#cashflow-preview [data-controller='preview-sankey-chart']", count: 2
    assert_select "#cashflow-preview [data-cash-flow-url-value*='/dashboard/cash_flow?']", count: 1
    assert_equal legacy, css_select("[data-controller='sankey-chart']").map { |chart| chart["data-sankey-chart-data-value"] }
  end

  test "a family member's preview opt-in does not expose the preview to this user" do
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => false))
    @user.family.users.where.not(id: @user.id).first.update!(preferences: { "preview_features_enabled" => true })
    get root_path
    assert_response :success
    assert_select "#cashflow-preview", count: 0
  end

  test "legacy telemetry configuration cannot load SDKs or surveys" do
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => true))
    with_env_overrides("POSTHOG_KEY" => "legacy-project", "POSTHOG_FEEDBACK_KEY" => "legacy-feedback",
      "POSTHOG_SANKEY_SURVEY_ID" => "legacy-survey", "POSTHOG_SELF_HOSTED_SANKEY_SURVEY_ID" => "legacy-survey",
      "POSTHOG_DEVELOPMENT_ENABLED" => "true", "SENTRY_DSN" => "https://key@example.test/1") do
      Rails.env.stubs(:production?).returns(true)
      get root_path
      assert_response :success
      assert_select "#cashflow-preview", count: 1
      assert_select "#cashflow-preview-feedback-dialog, [data-action='sankey-preview#feedback']", count: 0
      assert_select "script", text: /posthog|sentry/i, count: 0
      assert_select "[data-sankey-preview-survey-id-value], [data-sankey-preview-feedback-key-value]", count: 0
    end
  end
end
