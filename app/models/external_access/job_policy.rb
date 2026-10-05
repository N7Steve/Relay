class ExternalAccess::JobPolicy
  BANK_JOBS = %w[SyncAllJob SyncAllProvidersJob].freeze

  def self.capability(job_name)
    return :bank_sync if BANK_JOBS.include?(job_name)
    :google_drive if %w[DispatchGoogleDriveExportsJob GoogleDriveExportJob].include?(job_name)
  end
end
