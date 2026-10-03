require "test_helper"

class CashFlowPreviewTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    Rails.configuration.x.posthog.stubs(:development_enabled).returns(false)
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
    assert_select "#cashflow-preview[data-sankey-preview-relay-version-value=?]", Rails.root.join(".relay-version").read.strip
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

  test "self-hosted production feedback requires its own explicit project and survey" do
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => true))
    config = Rails.configuration.x.posthog
    config.stubs(:api_key).returns(nil)
    stub_managed_survey(nil)
    config.stubs(:self_hosted_feedback_project).returns({})
    config.stubs(:feedback_enabled).returns(true)
    with_self_hosting do
      get root_path
      assert_select "#cashflow-preview[data-sankey-preview-self-hosted-value='true'][data-sankey-preview-feedback-key-value=''][data-sankey-preview-survey-id-value='']"
      Rails.env.stubs(:production?).returns(true)
      get root_path
      assert_select "#cashflow-preview[data-sankey-preview-feedback-key-value=''][data-sankey-preview-survey-id-value='']"
      stub_self_hosted_feedback
      get root_path
      assert_select "#cashflow-preview[data-sankey-preview-feedback-key-value='test-feedback-project'][data-sankey-preview-survey-id-value='test-feedback-survey']"
      config.stubs(:api_key).returns("operator-owned-project")
      stub_managed_survey("operator-owned-survey")
      get root_path
      assert_select "#cashflow-preview[data-sankey-preview-feedback-key-value='test-feedback-project'][data-sankey-preview-survey-id-value='test-feedback-survey']"
      config.stubs(:feedback_enabled).returns(false)
      get root_path
      assert_select "#cashflow-preview[data-sankey-preview-feedback-key-value=''][data-sankey-preview-survey-id-value='']"
    end
  end

  test "self-hosted development renders configured feedback only with testing override" do
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => true))
    config = Rails.configuration.x.posthog
    config.stubs(:api_key).returns(nil)
    config.stubs(:feedback_enabled).returns(true)
    stub_managed_survey(nil)
    Rails.env.stubs(:development?).returns(true)
    stub_self_hosted_feedback
    with_self_hosting do
      get root_path
      assert_select "#cashflow-preview[data-sankey-preview-feedback-key-value=''][data-sankey-preview-survey-id-value='']"
      config.stubs(:development_enabled).returns(true)
      get root_path
      assert_select "#cashflow-preview[data-sankey-preview-feedback-key-value='test-feedback-project'][data-sankey-preview-survey-id-value='test-feedback-survey']"
      assert_select "script", text: /window.posthog=e/
      config.stubs(:feedback_enabled).returns(false)
      get root_path
      assert_select "#cashflow-preview[data-sankey-preview-feedback-key-value=''][data-sankey-preview-survey-id-value='']"
    end
  end

  test "development loads configured popup surveys only with testing override" do
    Rails.env.stubs(:development?).returns(true)
    Rails.configuration.x.posthog.stubs(:api_key).returns("configured-test-project")
    get root_path
    assert_select "head script", text: /posthog.init\('configured-test-project'/, count: 0
    Rails.configuration.x.posthog.stubs(:development_enabled).returns(true)
    get root_path
    assert_select "head script", text: /posthog.init\('configured-test-project'/
    assert_select "head script", text: /client.register\(\{ relay_version: #{Regexp.escape(Rails.root.join(".relay-version").read.strip.to_json)}/
  end

  test "managed app and demo use the configured environment survey without the shared feedback client" do
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => true))
    Rails.configuration.stubs(:app_mode).returns("managed".inquiry)
    Rails.env.stubs(:production?).returns(true)
    [ "app-survey", "demo-survey" ].each do |survey_id|
      stub_managed_survey(survey_id)
      get root_path
      assert_select "#cashflow-preview[data-sankey-preview-self-hosted-value='false'][data-sankey-preview-feedback-key-value=''][data-sankey-preview-survey-id-value='#{survey_id}']"
    end
  end

  private
    def stub_self_hosted_feedback
      config = Rails.configuration.x.posthog
      config.stubs(:self_hosted_feedback_project).returns(api_key: "test-feedback-project", host: "https://feedback.example.test")
      surveys = config.feedback_surveys
      config.stubs(:feedback_surveys).returns(surveys.merge(sankey: surveys.fetch(:sankey).merge(self_hosted: "test-feedback-survey")))
    end

    def stub_managed_survey(survey_id)
      config = Rails.configuration.x.posthog
      surveys = config.feedback_surveys
      config.stubs(:feedback_surveys).returns(surveys.merge(sankey: surveys.fetch(:sankey).merge(managed: survey_id)))
    end
end
