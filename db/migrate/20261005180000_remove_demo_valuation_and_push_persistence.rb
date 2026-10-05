class RemoveDemoValuationAndPushPersistence < ActiveRecord::Migration[8.1]
  SETTINGS = %w[demo_family_refresh_enabled demo_family_refresh_family_id external_property_valuations_enabled rentcast_api_key realie_api_key].freeze
  # Well-known key minted by the retired demo generator. Without the demo guard
  # it would be an ordinary valid credential, so it must not survive.
  DEMO_MONITORING_KEY = "demo_monitoring_key_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6".freeze

  # Migration-local reader: display_key uses the same deterministic encryption
  # as ApiKey, so the lookup works with and without encryption configured.
  class MigrationApiKey < ActiveRecord::Base
    self.table_name = "api_keys"
    encrypts :display_key, deterministic: true if ActiveRecordEncryptionConfig.explicitly_configured?
  end

  def up
    drop_table :push_subscriptions
    drop_table :provider_request_counts
    remove_check_constraint :properties, name: "properties_avm_provider_check"
    remove_index :properties, name: "index_properties_on_avm_provider_sync"
    remove_column :properties, :avm_provider
    remove_column :properties, :avm_last_synced_on
    execute "DELETE FROM settings WHERE var IN (#{SETTINGS.map { |name| connection.quote(name) }.join(', ')})"
    MigrationApiKey.where(display_key: DEMO_MONITORING_KEY).delete_all
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
