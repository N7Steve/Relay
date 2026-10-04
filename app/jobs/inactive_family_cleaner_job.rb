class InactiveFamilyCleanerJob < ApplicationJob
  # Compatibility for jobs queued before SaaS retirement. No side effects.
  def perform(dry_run: false)
    Rails.logger.info("Ignored retired commercial job: InactiveFamilyCleanerJob")
  end
end
