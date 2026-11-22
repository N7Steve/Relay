require "test_helper"

class AndroidAppsControllerTest < ActionDispatch::IntegrationTest
  APK = "signed-apk-fixture".b

  setup do
    @dir = Pathname.new(Dir.mktmpdir("relay-android-app-"))
    AndroidRelease.stubs(:directory).returns(@dir)
  end

  teardown do
    FileUtils.remove_entry(@dir) if @dir
  end

  test "requires a signed-in user" do
    write_release

    get android_app_path

    assert_redirected_to new_session_path
  end

  test "downloads the bundled APK" do
    write_release
    sign_in users(:family_admin)

    get android_app_path

    assert_response :success
    assert_equal "application/vnd.android.package-archive", response.media_type
    assert_includes response.headers["Content-Disposition"], "relay-0.1.42.apk"
    assert_equal APK, response.body.b
  end

  test "reports a server without an Android build" do
    sign_in users(:family_admin)

    get android_app_path

    assert_response :not_found
  end

  private

    def write_release
      File.binwrite(@dir.join("relay.apk"), APK)
      File.write(@dir.join("update.json"), JSON.generate(
        version_code: 42, version_name: "0.1.42", application_id: "app.relay.android", min_sdk: 26,
        size: APK.bytesize, sha256: Digest::SHA256.hexdigest(APK), commit: "b" * 40
      ))
    end
end
