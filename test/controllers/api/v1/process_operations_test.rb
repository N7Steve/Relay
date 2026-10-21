# frozen_string_literal: true

require "test_helper"

class Api::V1::ProcessOperationsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @key = ApiKey.create!(user: @user, name: "Processes", scopes: %w[read_write], source: "web", display_key: "processes_#{SecureRandom.hex(12)}")
  end

  test "rules validate references preview expire on changed data and execute once" do
    invoke("create_rule", name: "Coffee", conditions: [ { condition_type: "transaction_name", operator: "like", value: "Starbucks" } ], actions: [ { action_type: "set_transaction_name", value: "Coffee" } ], idempotency_key: "rule")
    assert_response :success, response.body
    id = response.parsed_body.fetch("id")
    invoke("preview_rule_run", rule_id: id)
    assert_response :success, response.body
    token = response.parsed_body.fetch("preview_token")
    target = entries(:transaction)
    target.update!(notes: "changed after preview")
    invoke("apply_rule", rule_id: id, preview_token: token, idempotency_key: "stale-run")
    assert_response :unprocessable_entity
    invoke("preview_rule_run", rule_id: id)
    token = response.parsed_body.fetch("preview_token")
    args = { rule_id: id, preview_token: token, ignore_attribute_locks: true, idempotency_key: "run" }
    assert_difference "RuleRun.count", 1 do
      invoke("apply_rule", args)
      assert_response :success, response.body
      invoke("apply_rule", args)
      assert_response :success
    end
    assert_equal "Coffee", target.reload.name
    invoke("list_rule_runs", rule_id: id)
    assert_response :success
    invoke("get_rule_options", {})
    assert_response :success, response.body
    invoke("delete_rule", rule_id: id, idempotency_key: "delete-rule")
    assert_response :success
  end

  test "CSV import rows and mapping editing preview publication retry and revert" do
    token = stage("date,name,amount,currency\n#{Date.current.iso8601},Imported coffee,12.5,USD\n", "movements.csv", "text/csv")
    invoke("start_import", type: "TransactionImport", upload_token: token, account_id: accounts(:depository).id, date_col_label: "date", name_col_label: "name", amount_col_label: "amount", currency_col_label: "currency", date_format: "%Y-%m-%d", idempotency_key: "import")
    assert_response :success, response.body
    id = response.parsed_body.fetch("id")
    invoke("list_import_rows", import_id: id)
    assert_response :success, response.body
    row_id = response.parsed_body.fetch("data").first.fetch("id")
    invoke("update_import_row", import_id: id, row_id: row_id, values: { name: "Corrected coffee" }, idempotency_key: "correct-row")
    assert_response :success
    invoke("list_import_mappings", import_id: id)
    assert_response :success
    invoke("preview_import", import_id: id)
    assert_response :success, response.body
    preview = response.parsed_body.fetch("preview_token")
    assert_enqueued_with(job: ApiProcessJob) do
      invoke("publish_import", import_id: id, preview_token: preview, idempotency_key: "publish")
      assert_response :success, response.body
    end
    row = Import.find(id)
    ApiProcessJob.perform_now("publish", row, authority)
    assert row.reload.complete?, row.error
    assert_equal 1, row.entries.count
    assert_no_difference "Entry.count" do
      invoke("publish_import", import_id: id, preview_token: preview, idempotency_key: "publish")
      assert_response :success, response.body
    end
    invoke("preview_revert_import", import_id: id)
    assert_response :success
    token = response.parsed_body.fetch("preview_token")
    invoke("revert_import", import_id: id, preview_token: token, idempotency_key: "revert")
    assert_response :success, response.body
    ApiProcessJob.perform_now("revert", row, authority)
    assert_equal 0, row.entries.count
  end

  test "uploads enforce checksum key collision and actor binding" do
    bytes = "private original"
    file = upload(bytes, "original.txt", "text/plain")
    post "/api/v1/files", params: { file: file, sha256: "0" * 64, idempotency_key: "bad" }, headers: headers
    assert_response :unprocessable_entity
    token = stage(bytes, "original.txt", "text/plain")
    invoke("upload_document", upload_token: token, idempotency_key: "document")
    assert_response :success, response.body
    id = response.parsed_body.fetch("id")
    get "/api/v1/files/download", params: { kind: "document", id: id }, headers: headers
    assert_response :success
    assert_equal bytes, response.body
    @key.update!(user: users(:family_member))
    invoke("upload_document", upload_token: token, idempotency_key: "stolen-upload")
    assert_response :forbidden
    get "/api/v1/files/download", params: { kind: "document", id: id }, headers: headers
    assert_response :forbidden
  end

  test "statement duplicate detection and authorized links preserve original bytes" do
    bytes = "date,description,amount\n2026-10-01,Statement line,12\n"
    token = stage(bytes, "statement.csv", "text/csv")
    invoke("upload_statement", upload_token: token, account_id: accounts(:depository).id, idempotency_key: "statement")
    assert_response :success, response.body
    id = response.parsed_body.fetch("id")
    invoke("upload_statement", upload_token: token, idempotency_key: "duplicate")
    assert_response :success, response.body
    assert_equal id, response.parsed_body.fetch("id")
    assert response.parsed_body.fetch("duplicate")
    invoke("unlink_statement", statement_id: id, idempotency_key: "unlink")
    assert_response :success
    invoke("reject_statement", statement_id: id, idempotency_key: "reject")
    assert_response :success
    invoke("link_statement", statement_id: id, account_id: accounts(:depository).id, idempotency_key: "link")
    assert_response :success
    get "/api/v1/files/download", params: { kind: "statement", id: id }, headers: headers
    assert_response :success
    assert_equal bytes, response.body
  end

  test "backup generation and protected downloads require full family authority" do
    assert_enqueued_with(job: ApiProcessJob) do
      invoke("create_family_backup", idempotency_key: "backup")
      assert_response :success, response.body
    end
    id = response.parsed_body.fetch("id")
    invoke("get_backup", backup_id: id)
    assert_response :success
    invoke("get_file_transfer", kind: "backup", id: id)
    assert_response :unprocessable_entity
    row = FamilyExport.find(id)
    row.export_file.attach(io: StringIO.new("archive"), filename: "archive.zip", content_type: "application/zip")
    row.update!(status: "completed")
    get "/api/v1/files/download", params: { kind: "backup", id: id }, headers: headers
    assert_response :success
    assert_equal "archive", response.body
    invoke("delete_backup", backup_id: id, idempotency_key: "delete-backup")
    assert_response :success
  end

  test "family admin cannot run global operations through a private member account" do
    accounts(:investment).update!(owner: users(:family_member))
    accounts(:investment).account_shares.where(user: @user).destroy_all
    invoke("list_rules", {})
    assert_response :forbidden
    invoke("list_imports", {})
    assert_response :forbidden
    invoke("create_family_backup", idempotency_key: "private-backup")
    assert_response :forbidden
  end

  test "full backup preflight restore and native readback preserve synthetic values and relations" do
    source = Family.create!(name: "Synthetic source", currency: "USD")
    source_account = source.accounts.create!(name: "Restored account", accountable: Depository.new, balance: 100, currency: "USD")
    source_account.entries.create!(name: "Original income", date: Date.current, amount: -25, currency: "USD", entryable: Transaction.new)
    bytes = Family::Backup.new(source).generate_ndjson
    @user = users(:empty)
    @key.update!(user: @user)
    token = stage(bytes, "backup.ndjson", "application/x-ndjson")
    invoke("start_import", type: "RelayImport", upload_token: token, idempotency_key: "restore-import")
    assert_response :success, response.body
    id = response.parsed_body.fetch("id")
    invoke("validate_backup", import_id: id)
    assert_response :success, response.body
    assert response.parsed_body.fetch("valid")
    assert response.parsed_body.fetch("destination_empty")
    preview = response.parsed_body.fetch("preview_token")
    invoke("restore_backup", import_id: id, preview_token: preview, idempotency_key: "restore")
    assert_response :success, response.body
    row = Import.find(id)
    ApiProcessJob.perform_now("publish", row, authority)
    assert row.reload.complete?, row.error
    restored = @user.family.accounts.find_by!(name: "Restored account")
    assert_equal 100.to_d, restored.balance
    assert_equal(-25.to_d, restored.entries.find_by!(name: "Original income").amount)
    assert row.verification_payload.present?
  end

  test "session chunks reject changed bytes and publication uses a fresh preview" do
    invoke("create_import_session", client_session_id: "chunks", expected_chunks: 1, idempotency_key: "session")
    assert_response :success, response.body
    id = response.parsed_body.fetch("id")
    content = "{\"type\":\"Account\",\"data\":{\"id\":\"source-account\",\"name\":\"Chunk account\",\"balance\":100,\"currency\":\"USD\",\"accountable_type\":\"Depository\"}}\n"
    token = stage(content, "chunk.ndjson", "application/x-ndjson")
    args = { session_id: id, upload_token: token, sequence: 1, client_chunk_id: "one", idempotency_key: "chunk" }
    invoke("upload_import_chunk", args)
    assert_response :success, response.body
    invoke("upload_import_chunk", args.merge(idempotency_key: "same-chunk"))
    assert_response :success
    assert_equal 1, ImportSession.find(id).imports.count
    changed = stage(content.sub("100", "101"), "chunk.ndjson", "application/x-ndjson")
    invoke("upload_import_chunk", args.merge(upload_token: changed, idempotency_key: "changed-chunk"))
    assert_response :unprocessable_entity
    invoke("preview_import_session", session_id: id)
    assert_response :success, response.body
    preview = response.parsed_body.fetch("preview_token")
    invoke("publish_import_session", session_id: id, preview_token: preview, idempotency_key: "publish-session")
    assert_response :success, response.body
  end

  test "eager NDJSON storage compensates rollback without retaining an orphan" do
    key = nil
    service = nil
    Import.transaction(requires_new: true) do
      row = @user.family.imports.create!(type: "RelayImport")
      row.attach_ndjson_content!(content: "original", filename: "rollback.ndjson", content_type: "application/x-ndjson")
      blob = row.ndjson_file.blob
      key, service = blob.key, blob.service
      assert_equal "original", blob.download
      raise ActiveRecord::Rollback
    end
    assert_not service.exist?(key)
  end

  private
    def headers
      { "X-Api-Key" => @key.display_key }
    end

    def authority
      Api::Access.new(user: @user, scopes: %w[read_write], credential: @key).delegated_authority
    end

    def invoke(name, args)
      post "/api/v1/actions/#{name}", params: { arguments: args }, headers: headers, as: :json
    end

    def upload(bytes, filename, content_type)
      file = Tempfile.new("api-upload")
      file.binmode
      file.write(bytes)
      file.rewind
      Rack::Test::UploadedFile.new(file.path, content_type, original_filename: filename)
    end

    def stage(bytes, filename, content_type)
      post "/api/v1/files", params: { file: upload(bytes, filename, content_type), sha256: Digest::SHA256.hexdigest(bytes), idempotency_key: SecureRandom.uuid }, headers: headers
      assert_response :created, response.body
      response.parsed_body.fetch("upload_token")
    end
end
