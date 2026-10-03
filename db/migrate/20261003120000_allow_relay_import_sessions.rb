class AllowRelayImportSessions < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :import_sessions, name: "chk_import_sessions_import_type"
    add_check_constraint :import_sessions,
                         "import_type IN ('SureImport', 'RelayImport')",
                         name: "chk_import_sessions_import_type"
  end

  def down
    # Hold the lock through the check and DDL in Rails' migration transaction.
    # A concurrent writer must not add a Relay session after the check.
    execute "LOCK TABLE import_sessions IN ACCESS EXCLUSIVE MODE"
    if connection.select_value("SELECT 1 FROM import_sessions WHERE import_type <> 'SureImport' LIMIT 1")
      raise ActiveRecord::IrreversibleMigration,
            "Relay import sessions exist. Keep the expanded constraint until their rollback is planned; no rows were changed."
    end

    remove_check_constraint :import_sessions, name: "chk_import_sessions_import_type"
    add_check_constraint :import_sessions,
                         "import_type = 'SureImport'",
                         name: "chk_import_sessions_import_type"
  end
end
