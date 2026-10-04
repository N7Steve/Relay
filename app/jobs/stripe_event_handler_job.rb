class StripeEventHandlerJob < ApplicationJob
  # Compatibility for jobs queued before SaaS retirement. No side effects.
  def perform(event_id)
    Rails.logger.info("Ignored retired commercial job: StripeEventHandlerJob")
  end
end
