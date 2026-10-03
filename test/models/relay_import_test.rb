require "test_helper"

class RelayImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "both persisted names resolve attachments and queued GlobalIDs" do
    Import::BACKUP_TYPES.each do |type|
      import = families(:empty).imports.create!(type: type)
      content = [
        { type: "Account", data: {
          id: "compat-account", name: "#{type} checking", balance: "100", currency: "USD", accountable_type: "Depository"
        } },
        { type: "Valuation", data: {
          id: "compat-valuation", account_id: "compat-account", date: "2024-01-01", amount: "100", currency: "USD", kind: "opening_anchor"
        } }
      ].map(&:to_json).join("\n")
      import.ndjson_file.attach(io: StringIO.new(content), filename: "all.ndjson", content_type: "application/x-ndjson")
      import.sync_ndjson_rows_count!

      loaded = Import.find(import.id)
      assert_instance_of type.constantize, loaded
      assert_equal content, loaded.ndjson_file.download
      assert_equal "Import", loaded.ndjson_file.attachment.record_type
      assert_not loaded.requires_csv_workflow?
      assert_equal 1, loaded.dry_run[:accounts]

      serialized = ImportJob.new(import).serialize
      assert_equal import.to_global_id.to_s, serialized["arguments"].first["_aj_globalid"]
      ActiveJob::Base.execute(serialized)

      import.reload
      assert import.complete?, import.error
      assert_equal "matched", import.verification_status
      assert_equal import.family, import.accounts.sole.family

      ActiveJob::Base.execute(RevertImportJob.new(import).serialize)
      assert import.reload.pending?
      assert_empty import.accounts
      assert import.ndjson_file.attached?
    end
  end

  test "legacy GlobalIDs also locate Relay records after a future type transition" do
    import = families(:empty).imports.create!(type: "RelayImport")
    [ GlobalID.app, "sure" ].uniq.each do |app|
      legacy_gid = GlobalID.create(import, app: app).to_s.sub("/RelayImport/", "/SureImport/")
      assert_equal import, GlobalID::Locator.locate(legacy_gid)
    end
    assert_instance_of RelayImport, SureImport.find(import.id)
  end

  test "Relay records preserve legacy preflight errors and limits" do
    import = families(:empty).imports.create!(type: "RelayImport")
    import.ndjson_file.attach(io: StringIO.new('{"type":"UnknownType","data":{}}'), filename: "all.ndjson", content_type: "application/x-ndjson")

    assert_raises(SureImport::PreflightError) { import.publish_later }
    assert_not import.publishable?

    with_env_overrides("RELAY_IMPORT_MAX_ROWS" => "1", "SURE_IMPORT_MAX_ROWS" => "2") do
      assert_equal 1, import.max_row_count
    end
  end

  test "session workers read Relay chunks without changing source mappings" do
    session = families(:empty).import_sessions.create!(import_type: "SureImport", client_session_id: "compat-session", expected_chunks: 1)
    chunk = session.attach_chunk!(sequence: 1, content: file_fixture("imports/relay.ndjson").read, filename: "all.ndjson", content_type: "application/x-ndjson")
    chunk.update!(type: "RelayImport")

    ActiveJob::Base.execute(ImportSessionJob.new(session).serialize)

    assert session.reload.complete?, session.error_details.inspect
    assert_instance_of RelayImport, session.imports.sole
    mapping = session.source_mappings.find_by!(source_type: "Account", source_id: "relay-browser-account")
    assert_equal session.family, mapping.target.family
    assert_equal session.family, mapping.family
    assert_equal "SureImport", session.import_type
  end
end
