class UseRelayImportSessionDefault < ActiveRecord::Migration[8.1]
  def change
    change_column_default :import_sessions, :import_type, from: "SureImport", to: "RelayImport"
  end
end
