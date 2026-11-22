# frozen_string_literal: true

# Serves the Android build bundled with this server to signed-in mobile clients.
# The client verifies size, SHA-256, version and signing certificate before
# handing the APK to the system installer.
class Api::V1::AndroidUpdatesController < Api::V1::BaseController
  before_action :ensure_read_scope

  rescue_from AndroidRelease::Invalid, with: :render_invalid_release

  # GET /api/v1/android/updates/latest
  def latest
    release = AndroidRelease.current
    render json: { enabled: release.present?, release: release&.as_json }
  end

  # GET /api/v1/android/updates/:version_code/apk
  def apk
    release = AndroidRelease.current
    unless release && params[:version_code] == release.version_code.to_s
      render json: { error: "not_found", message: "Android release not found" }, status: :not_found
      return
    end

    send_file release.apk_path,
      type: "application/vnd.android.package-archive",
      filename: "relay-#{release.version_name}.apk",
      disposition: "attachment"
  end

  private

    def ensure_read_scope
      authorize_scope!(:read)
    end

    def render_invalid_release(error)
      Rails.logger.error("[AndroidUpdates] #{error.message}")
      render json: { error: "android_release_unavailable", message: "The Android release on this server is invalid" },
        status: :service_unavailable
    end
end
