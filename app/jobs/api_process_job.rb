# frozen_string_literal: true

# Delegated jobs re-check the actor and credential at execution. Native callers
# keep their existing job paths; no credential secret is serialized to a queue.
class ApiProcessJob < ApplicationJob
  queue_as :high_priority

  def perform(operation, record, authority)
    access = Api::Access.from_delegation!(authority, family: record.family)
    raise Api::Access::Forbidden, "Delegated family authority changed" unless access.writable? && access.family_admin? && access.complete_account_visibility?
    record.family.accounts.each { |account| access.require_account!(account, :write) }
    case operation
    when "publish" then ImportJob.perform_now(record)
    when "session" then ImportSessionJob.perform_now(record)
    when "revert" then RevertImportJob.perform_now(record)
    when "backup" then FamilyDataExportJob.perform_now(record)
    else raise ArgumentError, "Unsupported delegated process"
    end
  rescue Api::Access::Forbidden => error
    if record.is_a?(Import)
      if record.importing? && record.data_committed?
        record.update!(status: "complete")
      elsif !record.complete?
        record.update!(status: record.reverting? ? "revert_failed" : "failed", error: error.message)
      end
    elsif record.is_a?(ImportSession)
      record.reconcile_committed_chunks!
      record.update!(status: "failed", error_details: { "code" => "delegated_authority_changed", "message" => error.message }) unless record.complete?
    elsif record.is_a?(FamilyExport)
      record.update!(status: "failed") unless record.completed?
    end
    DebugLogEntry.capture(category: "background_jobs", level: "warn", message: error.message, source: self.class.name,
      family: record.family, metadata: { record_id: record.id, operation: operation, user_id: authority["user_id"] })
  end
end
