# frozen_string_literal: true

# Staging references are short-lived and actor-bound. No storage URL is exposed.
class Api::FileTransfer
  MAX_BYTES = 100.megabytes
  TTL = 1.hour

  def self.verifier
    Rails.application.message_verifier("api_file_upload")
  end

  def self.store!(user:, file:, key:, sha256:)
    raise Api::Input::Invalid, "Upload key and SHA-256 required" unless key.is_a?(String) && key.length.in?(1..128) && sha256.to_s.match?(/\A[0-9a-f]{64}\z/)
    raise Api::Input::Invalid, "File required" unless file.respond_to?(:read)
    data = file.read(MAX_BYTES + 1)
    raise Api::Input::Invalid, "Empty or oversized file" unless data.bytesize.in?(1..MAX_BYTES)
    raise Api::Input::Invalid, "SHA-256 mismatch" unless Digest::SHA256.hexdigest(data) == sha256
    identity = Digest::SHA256.hexdigest([ user.id, key ].join(":"))
    blob = nil
    user.with_lock do
      blob = ActiveStorage::Blob.where("metadata::jsonb ->> 'relay_upload' = ?", identity).first
      if blob
        raise Api::Input::Invalid, "Upload key already used with different bytes or filename" unless blob.metadata["sha256"] == sha256 && blob.filename.to_s == File.basename(file.original_filename.to_s)
      else
        blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(data), filename: File.basename(file.original_filename.to_s), content_type: file.content_type,
          metadata: { relay_upload: identity, user_id: user.id, family_id: user.family_id, sha256: sha256 })
        ApiUploadCleanupJob.set(wait: TTL + 1.hour).perform_later(blob.id)
      end
    end
    raise Api::Input::Invalid, "Upload key expired; use a new key" if blob.created_at + TTL <= Time.current
    { upload_token: verifier.generate({ "blob_id" => blob.id, "user_id" => user.id, "family_id" => user.family_id }, expires_at: blob.created_at + TTL),
      filename: blob.filename.to_s, byte_size: blob.byte_size, sha256: sha256, expires_in: (blob.created_at + TTL - Time.current).to_i }
  end

  def self.resolve!(user:, token:)
    data = verifier.verified(token)
    raise ActiveRecord::RecordNotFound unless data && data["user_id"] == user.id && data["family_id"] == user.family_id
    blob = ActiveStorage::Blob.find(data.fetch("blob_id"))
    raise ActiveRecord::RecordNotFound unless blob.metadata["user_id"] == user.id && blob.metadata["family_id"] == user.family_id
    blob
  end

  def self.content!(blob)
    bytes = blob.download
    raise Api::Input::Invalid, "Uploaded file checksum mismatch" unless Digest::SHA256.hexdigest(bytes) == blob.metadata.fetch("sha256")
    bytes
  end
end
