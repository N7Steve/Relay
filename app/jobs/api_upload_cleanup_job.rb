# frozen_string_literal: true

class ApiUploadCleanupJob < ApplicationJob
  queue_as :low_priority

  def perform(blob_id)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    return unless blob && blob.metadata["relay_upload"] && blob.created_at + Api::FileTransfer::TTL < Time.current
    blob.purge unless blob.attachments.exists?
  end
end
