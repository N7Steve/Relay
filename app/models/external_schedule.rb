class ExternalSchedule
  JOB_CAPABILITIES = {
    "dispatch_google_drive_exports" => :google_drive
  }.freeze

  # Schedules removed in pruning phase 12 that may still be persisted in Redis.
  RETIRED_JOBS = %w[refresh_demo_family sync_property_valuations].freeze

  def self.reconcile!(schedule)
    RETIRED_JOBS.each { |name| Sidekiq::Cron::Job.find(name)&.destroy }
    schedule = schedule.except(*RETIRED_JOBS)
    enabled = schedule.reject do |name, _|
      capability = JOB_CAPABILITIES[name]
      disabled = capability && !ExternalAccess.enabled?(capability)
      Sidekiq::Cron::Job.find(name)&.destroy if disabled
      disabled
    end
    Sidekiq::Cron::Job.load_from_hash(enabled)
  end
end
