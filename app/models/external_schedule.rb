class ExternalSchedule
  JOB_CAPABILITIES = {
    "sync_property_valuations" => :property_valuations,
    "dispatch_google_drive_exports" => :google_drive
  }.freeze

  def self.reconcile!(schedule)
    enabled = schedule.reject do |name, _|
      capability = JOB_CAPABILITIES[name]
      disabled = capability && !ExternalAccess.enabled?(capability)
      Sidekiq::Cron::Job.find(name)&.destroy if disabled
      disabled
    end
    Sidekiq::Cron::Job.load_from_hash(enabled)
  end
end
