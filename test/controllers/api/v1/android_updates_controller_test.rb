# frozen_string_literal: true

require "test_helper"

class Api::V1::AndroidUpdatesControllerTest < ActionDispatch::IntegrationTest
  APK = "signed-apk-fixture".b

  setup do
    @user = users(:family_admin)
    @user.api_keys.active.destroy_all
    @api_key = ApiKey.create!(
      user: @user,
      name: "Test Read Key",
      scopes: [ "read" ],
      display_key: "test_ro_#{SecureRandom.hex(8)}",
      source: "mobile"
    )
    Redis.new.del("api_rate_limit:#{@api_key.id}")

    @dir = Pathname.new(Dir.mktmpdir("relay-android-release-"))
    AndroidRelease.stubs(:directory).returns(@dir)
  end

  teardown do
    FileUtils.remove_entry(@dir) if @dir
  end

  test "requires authentication" do
    get "/api/v1/android/updates/latest"
    assert_response :unauthorized

    write_release
    get "/api/v1/android/updates/1234/apk"
    assert_response :unauthorized
  end

  test "reports a disabled channel when the image has no Android build" do
    get "/api/v1/android/updates/latest", headers: api_headers

    assert_response :success
    assert_equal({ "enabled" => false, "release" => nil }, JSON.parse(response.body))
  end

  test "returns the bundled release manifest" do
    write_release

    get "/api/v1/android/updates/latest", headers: api_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert body["enabled"]
    assert_equal 1234, body.dig("release", "version_code")
    assert_equal "0.1.1234", body.dig("release", "version_name")
    assert_equal "app.relay.android", body.dig("release", "application_id")
    assert_equal APK.bytesize, body.dig("release", "size")
    assert_equal Digest::SHA256.hexdigest(APK), body.dig("release", "sha256")
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "downloads the APK for the published version only" do
    write_release

    get "/api/v1/android/updates/1234/apk", headers: api_headers

    assert_response :success
    assert_equal "application/vnd.android.package-archive", response.media_type
    assert_equal APK, response.body.b

    get "/api/v1/android/updates/1233/apk", headers: api_headers
    assert_response :not_found
  end

  test "refuses a manifest that does not match its APK" do
    write_release(size: APK.bytesize + 1)

    get "/api/v1/android/updates/latest", headers: api_headers

    assert_response :service_unavailable
    assert_equal "android_release_unavailable", JSON.parse(response.body)["error"]
  end

  test "refuses a manifest for another application" do
    write_release(application_id: "com.example.other")

    get "/api/v1/android/updates/1234/apk", headers: api_headers

    assert_response :service_unavailable
  end

  private

    def api_headers
      { "X-Api-Key" => @api_key.display_key }
    end

    def write_release(**overrides)
      File.binwrite(@dir.join("relay.apk"), APK)
      manifest = {
        version_code: 1234,
        version_name: "0.1.1234",
        application_id: "app.relay.android",
        min_sdk: 26,
        size: APK.bytesize,
        sha256: Digest::SHA256.hexdigest(APK),
        commit: "a" * 40
      }.merge(overrides)
      File.write(@dir.join("update.json"), JSON.generate(manifest))
    end
end
