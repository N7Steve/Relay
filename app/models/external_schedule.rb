class ExternalSchedule
  JOB_CAPABILITIES = {
    "sync_property_valuations" => :property_valuations,
    "dispatch_google_drive_exports" => :google_drive
  }.freeze

  # Owned schedules removed by pruning, including definitions already persisted in Redis.
  RETIRED_JOBS = %w[
    clean_inactive_families sync_hourly generate_recurring_occurrences process_financekit_inbox
    import_market_data run_security_health_checks
  ].freeze

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
