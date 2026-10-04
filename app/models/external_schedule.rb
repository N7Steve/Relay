class ExternalSchedule
  JOB_CAPABILITIES = {
    "import_market_data" => :market_data,
    "run_security_health_checks" => :market_data,
    "sync_hourly" => :bank_sync,
    "process_financekit_inbox" => :bank_sync,
    "sync_property_valuations" => :property_valuations,
    "dispatch_google_drive_exports" => :google_drive
  }.freeze

  def self.reconcile!(schedule)
    # Remove only this retired commercial cron, including persisted schedules.
    Sidekiq::Cron::Job.find("clean_inactive_families")&.destroy
    schedule = schedule.except("clean_inactive_families")
    enabled = schedule.reject do |name, _|
      capability = JOB_CAPABILITIES[name]
      disabled = capability && !ExternalAccess.enabled?(capability)
      Sidekiq::Cron::Job.find(name)&.destroy if disabled
      disabled
    end
    Sidekiq::Cron::Job.load_from_hash(enabled)
  end
end
