module Relay
  module Environment
    NAMES = %w[IMPORT_MAX_ROWS IMPORT_MAX_NDJSON_SIZE_MB BATCH_SIZE LIMIT DRY_RUN].freeze

    def self.fetch(name)
      ENV["RELAY_#{name}"]
    end

    # Report obsolete names to remap before migration, never their values.
    def self.legacy_names_in_use
      NAMES.filter_map do |name|
        "SURE_#{name}" if !ENV.key?("RELAY_#{name}") && ENV.key?("SURE_#{name}")
      end
    end
  end
end
