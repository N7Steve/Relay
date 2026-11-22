# The signed Android APK bundled into the server image by the local release
# (bin/release-local.py). An image built without it simply offers no update.
class AndroidRelease
  APPLICATION_ID = "app.relay.android"
  MAX_SIZE = 150.megabytes
  APK_FILENAME = "relay.apk"
  MANIFEST_FILENAME = "update.json"

  Invalid = Class.new(StandardError)

  attr_reader :version_code, :version_name, :application_id, :min_sdk, :size, :sha256, :commit, :apk_path

  class << self
    def directory
      Pathname.new(ENV["RELAY_ANDROID_RELEASE_DIR"].presence || Rails.root.join("android-release"))
    end

    # nil when this installation ships no Android build.
    def current(dir = directory)
      manifest = dir.join(MANIFEST_FILENAME)
      return unless manifest.file?

      new(JSON.parse(manifest.read), dir.join(APK_FILENAME))
    rescue JSON::ParserError
      raise Invalid, "Android update manifest is not valid JSON"
    end
  end

  def initialize(attributes, apk_path)
    @version_code = attributes["version_code"]
    @version_name = attributes["version_name"]
    @application_id = attributes["application_id"]
    @min_sdk = attributes["min_sdk"]
    @size = attributes["size"]
    @sha256 = attributes["sha256"]
    @commit = attributes["commit"]
    @apk_path = Pathname.new(apk_path)
    validate!
  end

  def as_json(*)
    {
      version_code: version_code,
      version_name: version_name,
      application_id: application_id,
      min_sdk: min_sdk,
      size: size,
      sha256: sha256,
      commit: commit
    }
  end

  private

    def validate!
      valid = version_code.is_a?(Integer) && version_code.between?(1, 2_100_000_000) &&
        version_name.is_a?(String) && version_name.match?(/\A[0-9A-Za-z.\-+]{1,64}\z/) &&
        application_id == APPLICATION_ID &&
        min_sdk.is_a?(Integer) && min_sdk.between?(26, 100) &&
        size.is_a?(Integer) && size.between?(1, MAX_SIZE) &&
        sha256.is_a?(String) && sha256.match?(/\A[0-9a-f]{64}\z/) &&
        commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/)
      raise Invalid, "Android update manifest has invalid fields" unless valid
      raise Invalid, "Android APK does not match its manifest" unless apk_path.file? && apk_path.size == size
    end
end
