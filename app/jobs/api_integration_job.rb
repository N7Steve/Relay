# frozen_string_literal: true

class ApiIntegrationJob < ApplicationJob
  queue_as :high_priority

  def perform(operation, record, authority)
    resource = record.is_a?(Sync) ? record.syncable : record
    family = resource.is_a?(Family) ? resource : resource.family
    access = Api::Access.from_delegation!(authority, family: family)
    case operation
    when "account"
      access.require_account!(resource, :write)
      ExternalAccess.locally { SyncJob.perform_now(record, balances_only: true) } if record.pending?
    when "family", "bank"
      raise Api::Access::Forbidden, "Complete family authority required" unless access.family_admin? && access.complete_account_visibility?
      family.accounts.each { |account| access.require_account!(account, :write) }
      ExternalAccess.require!(:bank_sync) if operation == "bank"
      SyncJob.perform_now(record) if record.pending?
    when "drive"
      raise Api::Access::Forbidden, "Drive schedule ownership changed" unless resource.user_id == access.user.id && resource.valid?
      ExternalAccess.require!(:google_drive)
      GoogleDriveExportJob.perform_now(resource, triggered_by: "manual")
    when "insights"
      raise Api::Access::Forbidden, "Preview or family visibility changed" unless access.user.preview_features_enabled? && access.complete_account_visibility?
      GenerateInsightsJob.perform_now(family_id: family.id)
    else
      raise ArgumentError, "Unsupported delegated integration"
    end
  rescue Api::Access::Forbidden, ExternalAccess::Disabled => error
    record.request_cancel! if record.is_a?(Sync)
    record.update!(status: "needs_attention", last_error_code: "access_changed") if record.is_a?(GoogleDriveExportSchedule)
    DebugLogEntry.capture(category: "background_jobs", level: "warn", message: error.message, source: self.class.name,
      family: family, metadata: { record_id: record.id, operation: operation, user_id: authority["user_id"] })
  end
end
