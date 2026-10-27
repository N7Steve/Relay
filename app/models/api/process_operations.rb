# frozen_string_literal: true

module Api::ProcessOperations
  def get_upload_channel(_args)
    { api_path: "/api/v1/files", mcp_path: "/mcp/files", method: "POST", encoding: "multipart/form-data",
      fields: %w[file idempotency_key sha256], max_bytes: Api::FileTransfer::MAX_BYTES, expires_in: Api::FileTransfer::TTL.to_i,
      authentication: "Use the same credential on its own API or MCP path; upload tokens remain bound to the actor" }
  end

  def list_rules(args)
    paginate(family.rules.order(:id), args) { |row| rule_json(row) }
  end

  def get_rule(args)
    rule_json(process_rule(args))
  end

  def get_rule_options(_args)
    rule = family.rules.new(resource_type: "transaction")
    { conditions: rule.condition_filters.map(&:as_json), actions: rule.action_executors.map(&:as_json) }
  end

  def create_rule(args)
    row = family.rules.new(resource_type: "transaction")
    assign_process_rule(row, args)
    row.save!
    rule_json(row)
  end

  def update_rule(args)
    row = process_rule(args)
    assign_process_rule(row, args)
    row.save!
    rule_json(row.reload)
  end

  def delete_rule(args)
    process_rule(args).destroy!
    { deleted: true }
  end

  def preview_rule_run(args)
    row = process_rule(args)
    plan = rule_plan(row)
    { rule_id: row.id, count: plan[:rows].length, transaction_ids: plan[:rows].map(&:id), actions: row.actions.map { |item| item.attributes.slice("action_type", "value") },
      preview_token: process_preview("rule", row.id, plan[:fingerprint]), expires_in: 600 }
  end

  def apply_rule(args)
    row = process_rule(args)
    row.with_lock do
      plan = rule_plan(row, lock: true)
      verify_process_preview!(args, "rule", row.id, plan[:fingerprint])
      run = row.rule_runs.create!(rule_name: row.name, execution_type: "manual", status: "pending", executed_at: Time.current, transactions_queued: plan[:rows].size)
      result = row.apply(resource_scope: family.transactions.where(id: plan[:rows].map(&:id)), ignore_attribute_locks: args.fetch("ignore_attribute_locks", false), rule_run: run)
      async = result.is_a?(Hash)
      run.update!(status: async ? "pending" : "success", transactions_processed: plan[:rows].size, transactions_modified: async ? result.fetch(:modified_count, 0) : result, pending_jobs_count: async ? result.fetch(:jobs_count, 0) : 0)
      financial_json(run.attributes)
    end
  end

  def list_rule_runs(args)
    paginate(process_rule(args).rule_runs.order(executed_at: :desc, id: :asc), args) { |row| financial_json(row.attributes) }
  end

  def list_imports(args)
    paginate(family.imports.order(created_at: :desc, id: :asc), args) { |row| import_json(row) }
  end

  def get_import(args)
    import_json(process_import(args))
  end

  def start_import(args)
    blob = upload_blob(args)
    content = Api::FileTransfer.content!(blob)
    attrs = args.slice(*Import::Preflight::CONFIG_PARAM_KEYS.map(&:to_s), "account_id", "qif_date_format", "type")
    row = family.imports.new(attrs.merge(user: user))
    row.original_file.attach(blob)
    if row.is_a?(SureImport)
      content, filename, content_type = SureImport::Upload.read(uploaded_file(blob, content))
      invalid!("Invalid backup content") unless SureImport.valid_ndjson_first_line?(content)
      row.save!
      row.attach_ndjson_content!(content: content, filename: filename, content_type: content_type)
      row.sync_ndjson_rows_count!
    else
      invalid!("Import exceeds size limit") if content.bytesize > Import.max_csv_size
      row.raw_file_str = content
      row.save!
      row.generate_rows_from_csv
      row.reload.sync_mappings
    end
    import_json(row.reload)
  end

  def configure_import(args)
    row = editable_import(args)
    attrs = args.slice(*Import::Preflight::CONFIG_PARAM_KEYS.map(&:to_s), "account_id", "qif_date_format")
    invalid!("Backup configuration is fixed") if row.is_a?(SureImport)
    row.update!(attrs)
    row.generate_rows_from_csv
    row.reload.sync_mappings
    import_json(row.reload)
  end

  def apply_import_template(args)
    row, source = editable_import(args), family.imports.find(args.fetch("template_id"))
    invalid!("Template must be a completed import of the same type") unless source.complete? && source.type == row.type
    row.apply_template!(source)
    import_json(row.reload)
  end

  def select_qif_categories(args)
    row = editable_import(args)
    invalid!("QIF import required") unless row.is_a?(QifImport)
    categories, tags = args.fetch("categories"), args.fetch("tags")
    invalid!("Selection contains unknown categories or tags") unless (categories - row.row_categories).empty? && (tags - row.row_tags).empty?
    row.update!(column_mappings: row.column_mappings.to_h.merge("qif_selected_categories" => categories, "qif_selected_tags" => tags))
    row.rows.where(category: row.row_categories - categories).update_all(category: "")
    row.rows.each do |item|
      item.update_column(:tags, (item.tags_list & tags).join("|")) if item.tags.present?
    end
    row.sync_mappings
    import_json(row.reload)
  end

  def list_import_rows(args)
    paginate(process_import(args).rows_ordered, args) do |row|
      row.valid?
      financial_json(row.attributes).merge("errors" => row.errors.full_messages)
    end
  end

  def update_import_row(args)
    row = editable_import(args).rows.find(args.fetch("row_id"))
    row.update_and_sync(args.fetch("values"))
    row.valid?
    financial_json(row.attributes).merge("errors" => row.errors.full_messages)
  end

  def list_import_mappings(args)
    paginate(process_import(args).mappings.order(:id), args) { |row| financial_json(row.attributes) }
  end

  def update_import_mapping(args)
    row = editable_import(args).mappings.find(args.fetch("mapping_id"))
    target = row.mappable_class
    if args["mappable_id"]
      invalid!("This mapping has no record target") unless target && [ Account, Category, Tag, Merchant ].include?(target)
      scope = target == Tag ? family.personal_tags_for(user) : target.where(family_id: family.id)
      record = scope.find(args["mappable_id"])
      access.require_account!(record, :write) if record.is_a?(Account)
    end
    row.update!(mappable: record, create_when_empty: args.fetch("create_when_empty", false), value: args["value"])
    financial_json(row.attributes)
  end

  def preview_import(args)
    row = process_import(args)
    payload = row.is_a?(SureImport) ? row.sure_preflight.payload : { valid: row.publishable?, totals: row.dry_run }
    payload.merge(import_id: row.id, full_backup: row.is_a?(SureImport) && row.full_backup?, destination_empty: restore_destination_empty?,
      preview_token: process_preview("publish", row.id, import_fingerprint(row)), expires_in: 600)
  end

  def validate_backup(args)
    row = process_import(args)
    invalid!("Full backup required") unless row.is_a?(SureImport) && row.full_backup?
    preview_import(args)
  end

  def restore_backup(args)
    row = process_import(args)
    invalid!("Full backup and empty destination required") unless row.is_a?(SureImport) && row.full_backup? && restore_destination_empty?
    queue_process_import(args)
  end

  def publish_import(args)
    row = process_import(args)
    invalid!("Use restore_backup for a full backup") if row.is_a?(SureImport) && row.full_backup?
    queue_process_import(args)
  end

  def queue_process_import(args)
    row = process_import(args)
    row.with_lock do
      verify_process_preview!(args, "publish", row.id, import_fingerprint(row))
      invalid!("Session chunks must be published through their session") if row.import_session_id
      invalid!("Import cannot be published") unless row.pending? || row.failed?
      invalid!("Import is not publishable") unless row.publishable?
      row.publish_later(authority: access.delegated_authority)
    end
    import_json(row.reload)
  end

  def cancel_import(args)
    row = process_import(args)
    if row.pending? || row.failed?
      row.destroy!
      { deleted: true }
    else
      invalid!("Only a presumed-lost running import can be cancelled") unless row.force_fail!
      import_json(row.reload)
    end
  end

  def preview_revert_import(args)
    row = process_import(args)
    { import_id: row.id, entries: row.entries.count, accounts: row.accounts.count, revertable: row.revertable?,
      preview_token: process_preview("revert", row.id, import_fingerprint(row)), expires_in: 600 }
  end

  def revert_import(args)
    row = process_import(args)
    row.with_lock do
      verify_process_preview!(args, "revert", row.id, import_fingerprint(row))
      invalid!("Import is not revertable") unless row.revertable?
      row.revert_later(authority: access.delegated_authority)
    end
    import_json(row.reload)
  end

  def delete_import(args)
    row = process_import(args)
    invalid!("Revert or finish this import before deleting its history") unless row.pending? || row.failed?
    invalid!("Import already has committed data") if row.data_committed?
    row.destroy!
    { deleted: true }
  end

  def create_import_session(args)
    row = ImportSession.create_or_find_for!(family: family, import_type: "RelayImport", client_session_id: args.fetch("client_session_id"), expected_chunks: args.fetch("expected_chunks"))
    session_json(row)
  end

  def get_import_session(args)
    session_json(process_session(args))
  end

  def upload_import_chunk(args)
    row, blob = process_session(args), upload_blob(args)
    content, filename, content_type = SureImport::Upload.read(uploaded_file(blob, Api::FileTransfer.content!(blob)))
    invalid!("Invalid backup NDJSON") unless SureImport.valid_ndjson_first_line?(content)
    row.attach_chunk!(sequence: args.fetch("sequence"), client_chunk_id: args.fetch("client_chunk_id"), content: content, filename: filename, content_type: content_type)
    session_json(row.reload)
  end

  def preview_import_session(args)
    row = process_session(args)
    { session: session_json(row), preflights: row.imports.map { |chunk| chunk.sure_preflight.payload },
      preview_token: process_preview("session", row.id, session_fingerprint(row)), expires_in: 600 }
  end

  def publish_import_session(args)
    row = process_session(args)
    row.with_lock do
      verify_process_preview!(args, "session", row.id, session_fingerprint(row))
      row.publish_later(authority: access.delegated_authority)
    end
    session_json(row.reload)
  end

  def list_statements(args)
    scope = visible_statements
    scope = scope.where(account_id: args["account_id"]) if args["account_id"]
    paginate(scope.order(created_at: :desc, id: :asc), args) { |row| statement_json(row) }
  end

  def get_statement(args)
    statement_json(process_statement(args))
  end

  def upload_statement(args)
    blob = upload_blob(args)
    prepared = AccountStatement.prepare_upload!(uploaded_file(blob, Api::FileTransfer.content!(blob)))
    duplicate = AccountStatement.duplicate_for(family, prepared)
    if duplicate
      raise ActiveRecord::RecordNotFound unless duplicate.viewable_by?(user)
      return statement_json(duplicate).merge("duplicate" => true)
    end
    record = args["account_id"] ? account(args["account_id"], :write) : nil
    statement_json(AccountStatement.create_from_prepared_upload!(family: family, account: record, prepared_upload: prepared))
  end

  def update_statement(args)
    row = process_statement(args, write: true)
    row.update!(args.slice("institution_name_hint", "account_name_hint", "account_last4_hint", "period_start_on", "period_end_on", "opening_balance", "closing_balance", "currency"))
    statement_json(row)
  end

  def link_statement(args)
    row = process_statement(args, write: true)
    row.link_to_account!(account(args.fetch("account_id"), :write))
    statement_json(row)
  end

  def unlink_statement(args)
    row = process_statement(args, write: true)
    row.unlink!
    statement_json(row)
  end

  def reject_statement(args)
    row = process_statement(args, write: true)
    row.reject_match!
    statement_json(row)
  end

  def delete_statement(args)
    process_statement(args, write: true).destroy!
    { deleted: true }
  end

  def list_documents(args)
    paginate(family.family_documents.order(:id), args) { |row| document_json(row) }
  end

  def get_document(args)
    document_json(family.family_documents.find(args.fetch("document_id")))
  end

  def upload_document(args)
    blob = upload_blob(args)
    invalid!("Unsupported document extension") unless File.extname(blob.filename.to_s).downcase.in?(FamilyDocument::SUPPORTED_EXTENSIONS)
    row = family.family_documents.joins(:file_attachment).find_by(active_storage_attachments: { blob_id: blob.id })
    row ||= family.family_documents.create!(filename: blob.filename.to_s, status: "ready", file: blob)
    document_json(row)
  end

  def delete_document(args)
    family.family_documents.find(args.fetch("document_id")).destroy!
    { deleted: true }
  end

  def list_attachments(args)
    row = transaction_entry(args.fetch("transaction_id"), :read).transaction
    paginate(row.attachments.order(:id), args) { |item| file_json(item.blob).merge(id: item.id) }
  end

  def attach_transaction_file(args)
    row = transaction_entry(args.fetch("transaction_id"), :annotate).transaction
    blob = upload_blob(args)
    row.with_lock do
      row.attachments.attach(blob) unless row.attachments.exists?(blob_id: blob.id)
      row.save!
    end
    { id: row.attachments.find_by!(blob_id: blob.id).id, filename: blob.filename.to_s }
  end

  def delete_transaction_attachment(args)
    row = transaction_entry(args.fetch("transaction_id"), :write).transaction
    row.attachments.find(args.fetch("attachment_id")).destroy!
    { deleted: true }
  end

  def get_file_transfer(args)
    blob = authorized_process_file(args)
    query = args.slice("kind", "id", "attachment_id").to_query
    file_json(blob).merge(api_path: "/api/v1/files/download?#{query}", mcp_path: "/mcp/files/download?#{query}", method: "GET", authentication: "Required on every download; no bearer URL or storage redirect")
  end

  def list_backups(args)
    paginate(family.family_exports.full_backup.order(created_at: :desc, id: :asc), args) { |row| backup_json(row) }
  end

  def get_backup(args)
    backup_json(process_backup(args))
  end

  def create_family_backup(_args)
    row = family.family_exports.create!(requested_by: user)
    ApiProcessJob.perform_later("backup", row, access.delegated_authority)
    backup_json(row)
  end

  def cancel_backup(args)
    row = process_backup(args)
    invalid!("Only a presumed-lost backup can be cancelled") unless row.force_fail!
    backup_json(row)
  end

  def delete_backup(args)
    row = process_backup(args)
    invalid!("A backup is still running") if row.pending? || row.processing?
    row.destroy!
    { deleted: true }
  end

  # Used by the authenticated binary endpoints; never returns a storage URL.
  def authorized_process_file(args)
    case args.fetch("kind")
    when "statement" then process_statement({ "statement_id" => args.fetch("id") }).original_file.blob
    when "attachment"
      invalid!("attachment_id is required") unless args["attachment_id"]
      transaction_entry(args.fetch("id"), :read).transaction.attachments.find(args.fetch("attachment_id")).blob
    when "document"
      require_process_admin!
      family.family_documents.find(args.fetch("id")).file.blob
    when "backup"
      require_process_admin!
      row = family.family_exports.full_backup.find(args.fetch("id"))
      invalid!("Backup is not downloadable") unless row.downloadable?
      row.export_file.blob
    when "import"
      require_process_admin!
      row = family.imports.find(args.fetch("id"))
      if row.original_file.attached?
        row.original_file.blob
      elsif row.is_a?(SureImport) && row.ndjson_file.attached?
        row.ndjson_file.blob
      else
        invalid!("This historical import has no retained original")
      end
    else invalid!("Unknown file kind")
    end
  end

  private
    def authorize_process_arguments!(name, args)
      return unless Mcp::ProcessCatalog.definitions.any? { |tool| tool[:name] == name }
      unless name.in?(%w[get_upload_channel get_file_transfer list_statements get_statement list_attachments attach_transaction_file delete_transaction_attachment])
        if name.include?("statement")
          raise Api::Access::Forbidden, "Statement manager required" unless AccountStatement.statement_manager?(user)
        else
          require_process_admin!
        end
      end
      process_statement(args, write: !Mcp::Catalog.fetch(name)[:annotations][:readOnlyHint]) if args["statement_id"]
      process_import(args) if args["import_id"]
      process_session(args) if args["session_id"]
      upload_blob(args) if args["upload_token"]
    end

    def require_process_admin!
      raise Api::Access::Forbidden, "Family administrator and complete account visibility required" unless access.family_admin? && access.complete_account_visibility?
      if access.writable?
        family.accounts.each { |record| access.require_account!(record, :write) }
      end
    end

    def process_rule(args)
      family.rules.find(args.fetch("rule_id"))
    end

    def assign_process_rule(row, args)
      row.assign_attributes(args.slice("name", "effective_date", "active"))
      row.conditions.destroy_all if args["conditions"] && row.persisted?
      row.actions.destroy_all if args["actions"] && row.persisted?
      args.fetch("conditions", []).each { |attrs| row.conditions.build(attrs) }
      args.fetch("actions", []).each { |attrs| row.actions.build(attrs) }
      row.conditions.select(&:compound?).each do |item|
        invalid!("Compound conditions require and/or and child conditions") unless item.operator.in?(%w[and or]) && item.sub_conditions.any?
      end
      row.conditions.flat_map { |item| item.compound? ? item.sub_conditions : [ item ] }.each do |item|
        invalid!("Unsupported condition operator") unless item.filter.operators.map(&:last).include?(item.operator)
        invalid!("Unavailable condition value") if item.filter.type == "select" && !Rule::ConditionFilter::VALUELESS_OPERATORS.include?(item.operator) && !item.filter.options.to_a.map { |value| value.last.to_s }.include?(item.value)
      end
      row.actions.each do |item|
        executor = row.action_executors.find { |candidate| candidate.key == item.action_type }
        invalid!("Unsupported rule action") unless executor
        if executor.type.in?(%w[select multi_select])
          values = executor.type == "multi_select" ? item.value.to_s.split(",") : [ item.value ]
          invalid!("Unavailable action value") unless (values - executor.options.to_a.map { |value| value.last.to_s }).empty?
        end
      end
    end

    def rule_json(row)
      financial_json(row.attributes).merge("conditions" => row.conditions.map { |item| item.attributes.merge("sub_conditions" => item.sub_conditions.map(&:attributes)) }, "actions" => row.actions.map(&:attributes))
    end

    def rule_plan(row, lock: false)
      ids = row.matching_transaction_ids
      invalid!("Preview is limited to 100 matching transactions; narrow the rule") if ids.size > 100
      scope = family.transactions.where(id: ids).order(:id)
      scope = scope.lock if lock
      rows = scope.to_a
      Entry.where(id: rows.map { |item| item.entry.id }).order(:id).lock.load if lock
      rows.each { |item| access.require_account!(item.entry.account, :write) } if access.writable?
      { rows: rows, fingerprint: process_digest([ rule_json(row), rows.map { |item| [ item.attributes, item.entry.attributes, item.tag_ids.sort ] } ]) }
    end

    def process_import(args)
      row = family.imports.find(args.fetch("import_id"))
      raise ActiveRecord::RecordNotFound if row.account_statement && !row.account_statement.viewable_by?(user)
      row
    end

    def editable_import(args)
      row = process_import(args)
      invalid!("Only an uncommitted standalone import can be edited") unless (row.pending? || row.failed?) && !row.data_committed? && !row.import_session_id
      row
    end

    def import_json(row)
      financial_json(row.attributes.slice("id", "type", "status", "account_id", "rows_count", "error", "summary", "created_at", "updated_at", "import_session_id", "sequence", "checksum")).merge("name" => row.type)
    end

    def import_fingerprint(row)
      process_digest([ row.attributes, row.rows.order(:id).map(&:attributes), row.mappings.order(:id).map(&:attributes), row.entries.order(:id).map(&:attributes),
        row.is_a?(SureImport) && row.ndjson_file.attached? ? row.ndjson_file.blob.checksum : nil, destination_fingerprint ])
    end

    def destination_fingerprint
      process_digest(Family::Backup.new(family).records.sort_by { |row| [ row[:data][:model], row[:data][:attributes]["id"].to_s ] })
    end

    def restore_destination_empty?
      !family.accounts.exists? && !family.goals.exists? && !family.scheduled_payments.exists? && !family.budgets.exists? && !family.rules.exists?
    end

    def process_session(args)
      family.import_sessions.find(args.fetch("session_id"))
    end

    def session_json(row)
      financial_json(row.attributes).merge("chunks" => row.imports.map { |chunk| import_json(chunk) })
    end

    def session_fingerprint(row)
      process_digest([ row.attributes, row.imports.order(:sequence).map { |chunk| import_fingerprint(chunk) } ])
    end

    def process_digest(value)
      Digest::SHA256.hexdigest(JSON.generate(value))
    end

    def process_preview(kind, id, fingerprint)
      Rails.application.message_verifier("api_process_preview").generate({ "user_id" => user.id, "kind" => kind, "id" => id, "fingerprint" => fingerprint }, expires_in: 10.minutes)
    end

    def verify_process_preview!(args, kind, id, fingerprint)
      token = Rails.application.message_verifier("api_process_preview").verified(args.fetch("preview_token"))
      invalid!("Preview expired or data changed; preview again") unless token && token.values_at("user_id", "kind", "id", "fingerprint") == [ user.id, kind, id, fingerprint ]
    end

    def upload_blob(args)
      Api::FileTransfer.resolve!(user: user, token: args.fetch("upload_token"))
    end

    def uploaded_file(blob, bytes)
      # Same reader contract as a multipart upload, without a publicly signed blob.
      file = StringIO.new(bytes)
      file.define_singleton_method(:original_filename) { blob.filename.to_s }
      file.define_singleton_method(:content_type) { blob.content_type }
      file
    end

    def visible_statements
      scope = family.account_statements.where(account_id: access.accounts.select(:id))
      scope = scope.or(family.account_statements.where(account_id: nil)) if AccountStatement.statement_manager?(user)
      scope
    end

    def process_statement(args, write: false)
      row = visible_statements.find(args.fetch("statement_id"))
      raise Api::Access::Forbidden, "Statement management permission required" if write && !row.manageable_by?(user)
      access.require_account!(row.account, :write) if write && row.account
      row
    end

    def statement_json(row)
      financial_json(row.attributes.except("metadata", "parser_metadata")).except("suggested_account_id").merge("name" => row.filename)
    end

    def document_json(row)
      row.attributes.slice("id", "filename", "status", "created_at").merge("name" => row.filename, "original_available" => row.file.attached?)
    end

    def file_json(blob)
      { filename: blob.filename.to_s, byte_size: blob.byte_size, content_type: blob.content_type, checksum: blob.checksum, checksum_algorithm: "MD5/base64" }
    end

    def process_backup(args)
      family.family_exports.full_backup.find(args.fetch("backup_id"))
    end

    def backup_json(row)
      financial_json(row.attributes.slice("id", "status", "created_at", "updated_at", "error_message")).merge("name" => row.filename, "downloadable" => row.downloadable?)
    end
end
