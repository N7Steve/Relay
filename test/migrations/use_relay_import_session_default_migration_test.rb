require "test_helper"
require Rails.root.join("db/migrate/20261003130000_use_relay_import_session_default")

class UseRelayImportSessionDefaultMigrationTest < ActiveSupport::TestCase
  teardown { ImportSession.reset_column_information }

  test "changing the default leaves existing session types intact in both directions" do
    legacy = families(:empty).import_sessions.create!(import_type: "SureImport")
    relay = families(:empty).import_sessions.create!
    before = [ legacy.attributes, relay.attributes ]

    run_migration(:down)
    assert_equal "SureImport", families(:empty).import_sessions.create!.import_type
    assert_equal before, [ legacy.reload.attributes, relay.reload.attributes ]

    run_migration(:up)
    assert_equal "RelayImport", families(:empty).import_sessions.create!.import_type
    assert_equal before, [ legacy.reload.attributes, relay.reload.attributes ]
  end

  private
    def run_migration(direction)
      ActiveRecord::Migration.suppress_messages { UseRelayImportSessionDefault.new.migrate(direction) }
      ImportSession.reset_column_information
    end
end
