module FeedbackHelper
  def posthog_enabled?
    false
  end

  def feedback_config(_feature)
    {}
  end
end
