# First installation of the native Android app from a signed-in browser. Later
# versions are offered inside the app through /api/v1/android/updates.
class AndroidAppsController < ApplicationController
  def show
    release = AndroidRelease.current
    return head :not_found unless release

    response.headers["Cache-Control"] = "private, no-store"
    send_file release.apk_path,
      type: "application/vnd.android.package-archive",
      filename: "relay-#{release.version_name}.apk",
      disposition: "attachment"
  rescue AndroidRelease::Invalid => error
    Rails.logger.error("[AndroidApps] #{error.message}")
    head :service_unavailable
  end
end
