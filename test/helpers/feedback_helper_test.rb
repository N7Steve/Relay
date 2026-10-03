require "test_helper"

class FeedbackHelperTest < ActionView::TestCase
  test "telemetry and surveys stay disabled in every mode" do
    [ "production", "development", "test" ].each do |environment|
      Rails.stubs(:env).returns(environment.inquiry)
      assert_not posthog_enabled?
      assert_empty feedback_config(:sankey)
      assert_empty feedback_config(:unknown)
    end
  end
end
