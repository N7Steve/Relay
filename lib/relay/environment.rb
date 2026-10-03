module Relay
  module Environment
    NAMES = %w[IMPORT_MAX_ROWS IMPORT_MAX_NDJSON_SIZE_MB BATCH_SIZE LIMIT DRY_RUN].freeze

    def self.fetch(name)
      ENV.fetch("RELAY_#{name}") { ENV["SURE_#{name}"] }
    end

    # Report names only, never configuration values or secrets.
    def self.legacy_names_in_use
      NAMES.filter_map do |name|
        "SURE_#{name}" if !ENV.key?("RELAY_#{name}") && ENV.key?("SURE_#{name}")
      end
    end
  end
end
