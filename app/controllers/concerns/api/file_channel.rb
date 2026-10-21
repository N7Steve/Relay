# frozen_string_literal: true

module Api::FileChannel
  extend ActiveSupport::Concern

  included do
    include ActionController::Live
  end

  def upload
    authorize_scope!(:write)
    return if performed?
    render json: Api::FileTransfer.store!(user: current_resource_owner, file: params[:file], key: params[:idempotency_key], sha256: params[:sha256]), status: :created
  end

  def download
    authorize_scope!(:read)
    return if performed?
    args = params.permit(:kind, :id, :attachment_id).to_h
    Mcp::Catalog.validate!(Mcp::Catalog.fetch("get_file_transfer").fetch(:inputSchema), args)
    blob = Api::DailyOperations.new(access: api_access).authorized_process_file(args)
    # Stream through this authorized request; no redirect to a reusable blob URL.
    send_stream(filename: blob.filename.to_s, type: blob.content_type, disposition: :attachment) do |stream|
      blob.download { |chunk| stream.write(chunk) }
    end
  end
end
