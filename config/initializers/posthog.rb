require "posthog"

Rails.configuration.x.posthog = ActiveSupport::OrderedOptions.new
# Explicit opt-in for local browser testing.
Rails.configuration.x.posthog.development_enabled = ActiveModel::Type::Boolean.new.cast(ENV.fetch("POSTHOG_DEVELOPMENT_ENABLED", "false"))
Rails.configuration.x.posthog.api_key = ENV["POSTHOG_KEY"].presence
Rails.configuration.x.posthog.host = ENV.fetch("POSTHOG_HOST", "https://us.i.posthog.com")
Rails.configuration.x.posthog.feedback_enabled = ActiveModel::Type::Boolean.new.cast(ENV.fetch("POSTHOG_FEEDBACK_ENABLED", "true"))
# Feedback requires an operator-configured public client token and survey.
# Never supply a personal or administrative API key here.
Rails.configuration.x.posthog.self_hosted_feedback_project = {
  api_key: ENV["POSTHOG_FEEDBACK_KEY"].presence,
  host: ENV.fetch("POSTHOG_FEEDBACK_HOST", "https://us.i.posthog.com")
}.freeze
# Register each feature's survey separately from the configured project destination.
# Managed app/demo deployments provide the survey belonging to their own project.
Rails.configuration.x.posthog.feedback_surveys = {
  sankey: {
    managed: ENV["POSTHOG_SANKEY_SURVEY_ID"].presence,
    self_hosted: ENV["POSTHOG_SELF_HOSTED_SANKEY_SURVEY_ID"].presence
  }.freeze
}.freeze

if (api_key = Rails.configuration.x.posthog.api_key).present?
  # Initialize PostHog client
  $posthog = PostHog::Client.new({
    api_key: api_key,
    host: Rails.configuration.x.posthog.host,
    on_error: Proc.new { |status, msg| puts "PostHog error: #{status} - #{msg}" }
  })
end
