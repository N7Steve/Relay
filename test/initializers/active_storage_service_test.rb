require "test_helper"

class ActiveStorageServiceTest < ActiveSupport::TestCase
  INITIALIZER = Rails.root.join("config/initializers/active_storage_service.rb")

  test "only local disk services are configured" do
    services = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/storage.yml"))

    assert_equal %w[local test], services.keys.sort
    assert_equal %w[Disk], services.values.map { |service| service["service"] }.uniq
    assert_nil Gem.loaded_specs["aws-sdk-s3"]
    assert_nil Gem.loaded_specs["google-cloud-storage"]
  end

  test "remote storage services stop boot outside tests" do
    Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new("production"))

    %w[amazon cloudflare generic_s3 google].each do |service|
      with_env_overrides("ACTIVE_STORAGE_SERVICE" => service) do
        error = assert_raises(RuntimeError) { load INITIALIZER }
        assert_includes error.message, "ACTIVE_STORAGE_SERVICE=#{service} is no longer supported"
      end
    end
  end

  test "local or unset storage boots" do
    Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new("production"))

    [ "local", "", nil ].each do |service|
      with_env_overrides("ACTIVE_STORAGE_SERVICE" => service) { assert_nothing_raised { load INITIALIZER } }
    end
  end
end
