require "test_helper"

class Relay::EnvironmentTest < ActiveSupport::TestCase
  test "legacy diagnostics report only obsolete names needing migration" do
    cleared = Relay::Environment::NAMES.flat_map { |name| [ "RELAY_#{name}", "SURE_#{name}" ] }.index_with { nil }
    with_env_overrides(cleared.merge(
      "SURE_IMPORT_MAX_ROWS" => "150000",
      "SURE_IMPORT_MAX_NDJSON_SIZE_MB" => "64",
      "RELAY_IMPORT_MAX_NDJSON_SIZE_MB" => "",
      "SURE_DRY_RUN" => "false", "RELAY_DRY_RUN" => "true"
    )) do
      assert_equal [ "SURE_IMPORT_MAX_ROWS" ], Relay::Environment.legacy_names_in_use
    end
  end
end
