# frozen_string_literal: true

require "test_helper"

class Api::V1::FilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @key = ApiKey.create!(user: @user, name: "Files", scopes: %w[read_write], source: "web", display_key: "files_#{SecureRandom.hex(12)}")
  end

  test "binary channel rejects unauthenticated and read only uploads" do
    post "/api/v1/files", params: {}
    assert_response :unauthorized
    @key.update!(scopes: %w[read])
    post "/api/v1/files", params: {}, headers: { "X-Api-Key" => @key.display_key }
    assert_response :forbidden
  end

  test "upload retries preserve bytes reject collisions expire and clean unused staging" do
    file = StringIO.new("bytes")
    file.define_singleton_method(:original_filename) { "original.txt" }
    file.define_singleton_method(:content_type) { "text/plain" }
    first = Api::FileTransfer.store!(user: @user, file: file, key: "same", sha256: Digest::SHA256.hexdigest("bytes"))
    file.rewind
    second = Api::FileTransfer.store!(user: @user, file: file, key: "same", sha256: Digest::SHA256.hexdigest("bytes"))
    original = Api::FileTransfer.resolve!(user: @user, token: first[:upload_token])
    assert_equal original, Api::FileTransfer.resolve!(user: @user, token: second[:upload_token])
    assert_raises(ActiveRecord::RecordNotFound) { Api::FileTransfer.resolve!(user: users(:family_member), token: first[:upload_token]) }
    travel 2.hours do
      assert_raises(ActiveRecord::RecordNotFound) { Api::FileTransfer.resolve!(user: @user, token: first[:upload_token]) }
      ApiUploadCleanupJob.perform_now(original.id)
      assert_not ActiveStorage::Blob.exists?(original.id)
    end
  end

  test "cleanup preserves an attached original and collision cannot replace bytes" do
    file = StringIO.new("bytes")
    file.define_singleton_method(:original_filename) { "original.txt" }
    file.define_singleton_method(:content_type) { "text/plain" }
    result = Api::FileTransfer.store!(user: @user, file: file, key: "attached", sha256: Digest::SHA256.hexdigest("bytes"))
    blob = Api::FileTransfer.resolve!(user: @user, token: result[:upload_token])
    @user.family.family_documents.create!(filename: "original.txt", status: "ready", file: blob)
    file.reopen("changed")
    assert_raises(Api::Input::Invalid) { Api::FileTransfer.store!(user: @user, file: file, key: "attached", sha256: Digest::SHA256.hexdigest("changed")) }
    travel 2.hours do
      ApiUploadCleanupJob.perform_now(blob.id)
      assert_equal "bytes", blob.reload.download
    end
  end
end
