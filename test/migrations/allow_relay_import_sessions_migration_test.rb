require "test_helper"
require Rails.root.join("db/migrate/20261003120000_allow_relay_import_sessions")

class AllowRelayImportSessionsMigrationTest < ActiveSupport::TestCase
  setup do
    @session = families(:empty).import_sessions.create!(import_type: "SureImport", client_session_id: "schema-rollout", expected_chunks: 2)
  end

  test "upgrade preserves legacy sessions and default while allowing both backup types" do
    run_migration(:down)
    before = @session.reload.attributes

    run_migration(:up)

    assert_equal before, @session.reload.attributes
    assert_equal "RelayImport", database_default
    assert constraint_validated?
    set_database_type("RelayImport")
    assert_equal "RelayImport", @session.reload.import_type
    set_database_type("SureImport")
    assert_equal "SureImport", @session.reload.import_type
  end

  test "expanded constraint rejects unsupported and null types" do
    [ "TransactionImport", "relayimport", "", nil ].each do |type|
      assert_raises(ActiveRecord::StatementInvalid) do
        connection.transaction(requires_new: true) { set_database_type(type) }
      end
    end

    assert_equal "SureImport", @session.reload.import_type
  end

  test "rollback preserves legacy sessions and restores the validated legacy constraint" do
    before = @session.reload.attributes

    run_migration(:down)

    assert_equal before, @session.reload.attributes
    assert_equal "RelayImport", database_default
    assert constraint_validated?
    assert_raises(ActiveRecord::StatementInvalid) do
      connection.transaction(requires_new: true) { set_database_type("RelayImport") }
    end

    run_migration(:up)
    set_database_type("RelayImport")
    assert_equal "RelayImport", @session.reload.import_type
  end

  test "rollback refuses Relay sessions without changing data or the expanded constraint" do
    set_database_type("RelayImport")
    before = @session.reload.attributes

    error = assert_raises(ActiveRecord::IrreversibleMigration) { run_migration(:down) }

    assert_match "Relay import sessions exist", error.message
    assert_equal before, @session.reload.attributes
    assert constraint_validated?
    set_database_type("SureImport")
    set_database_type("RelayImport")
    assert_equal "RelayImport", @session.reload.import_type
  end

  test "normal session and chunk writers use Relay after schema expansion" do
    session = ImportSession.create_or_find_for!(
      family: families(:empty), import_type: "RelayImport",
      client_session_id: "legacy-writer", expected_chunks: 1
    )
    chunk = session.attach_chunk!(
      sequence: 1,
      content: { type: "Account", data: { id: "schema-account", name: "Schema account", currency: "USD", accountable_type: "Depository" } }.to_json,
      filename: "relay-import.ndjson", content_type: "application/x-ndjson"
    )

    assert_equal "RelayImport", session.reload.import_type
    assert_equal "RelayImport", chunk.reload.type
    assert_equal session.id, chunk.import_session_id
    retry_session = ImportSession.create_or_find_for!(
      family: families(:empty), import_type: "SureImport",
      client_session_id: "legacy-writer", expected_chunks: 1
    )
    assert_equal session.id, retry_session.id
    assert_equal "RelayImport", retry_session.import_type
  end

  private
    def connection = ActiveRecord::Base.connection

    def run_migration(direction)
      ActiveRecord::Migration.suppress_messages { AllowRelayImportSessions.new.public_send(direction) }
    end

    # Bypass the unchanged model validation to test the database rollout itself.
    def set_database_type(type)
      connection.execute("UPDATE import_sessions SET import_type = #{connection.quote(type)} WHERE id = #{connection.quote(@session.id)}")
    end

    def database_default
      connection.columns(:import_sessions).find { |column| column.name == "import_type" }.default
    end

    def constraint_validated?
      connection.select_value(<<~SQL)
        SELECT convalidated FROM pg_constraint
        WHERE conrelid = 'import_sessions'::regclass AND conname = 'chk_import_sessions_import_type'
      SQL
    end
end
