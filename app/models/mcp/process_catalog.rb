# frozen_string_literal: true

class Mcp::ProcessCatalog
  def self.definitions
    c = Mcp::Catalog
    rule = { rule_id: c::ID }
    import = { import_id: c::ID }
    session = { session_id: c::ID }
    statement = { statement_id: c::ID }
    backup = { backup_id: c::ID }
    upload = { upload_token: { type: "string", maxLength: 4000 } }
    preview = { preview_token: { type: "string", maxLength: 16000 } }
    condition = { type: "object", additionalProperties: false, required: %w[condition_type operator], properties: {
      condition_type: { type: "string", enum: Rule::Registry::TransactionResource.condition_filter_keys }, operator: c::STRING, value: c::STRING
    } }
    compound = condition.deep_dup
    compound[:properties][:condition_type] = { type: "string", enum: Rule::Condition::SUPPORTED_CONDITION_TYPES }
    compound[:properties][:sub_conditions_attributes] = { type: "array", minItems: 1, maxItems: 20, items: condition }
    action = { type: "object", additionalProperties: false, required: [ "action_type" ], properties: { action_type: c::STRING, value: c::STRING } }
    rule_attrs = { name: c::STRING, effective_date: c::DATE, active: c::BOOLEAN,
      conditions: { type: "array", maxItems: 100, items: compound }, actions: { type: "array", minItems: 1, maxItems: 8, items: action } }
    config = Import::Preflight::CONFIG_PARAM_KEYS.to_h { |key| [ key, key == :rows_to_skip ? { type: "integer", minimum: 0 } : c::STRING ] }
    config.merge!(account_id: c::ID, qif_date_format: c::STRING)
    row = %i[account date qty ticker price amount currency name category tags entity_type notes category_color category_classification category_parent category_icon].to_h { |key| [ key, c::STRING ] }
    file = { kind: { type: "string", enum: %w[statement document attachment backup import] }, id: c::ID, attachment_id: c::ID }
    tools = [
      c.definition("list_rules", c::PAGE, read: true),
      c.definition("get_rule", rule, required: [ "rule_id" ], read: true),
      c.definition("get_rule_options", {}, read: true),
      c.definition("create_rule", rule_attrs, required: %w[conditions actions]),
      c.definition("update_rule", rule.merge(rule_attrs), required: [ "rule_id" ]),
      c.definition("delete_rule", rule, required: [ "rule_id" ], destructive: true),
      c.definition("preview_rule_run", rule, required: [ "rule_id" ], read: true),
      c.definition("apply_rule", rule.merge(preview).merge(ignore_attribute_locks: c::BOOLEAN), required: %w[rule_id preview_token]),
      c.definition("list_rule_runs", c::PAGE.merge(rule), required: [ "rule_id" ], read: true),
      c.definition("list_imports", c::PAGE, read: true),
      c.definition("get_import", import, required: [ "import_id" ], read: true),
      c.definition("start_import", config.merge(upload).merge(type: { type: "string", enum: Import::TYPES - [ "PdfImport", "SureImport" ] }), required: %w[type upload_token]),
      c.definition("configure_import", import.merge(config), required: [ "import_id" ]),
      c.definition("select_qif_categories", import.merge(categories: { type: "array", maxItems: 100, items: c::STRING }, tags: { type: "array", maxItems: 100, items: c::STRING }), required: %w[import_id categories tags]),
      c.definition("apply_import_template", import.merge(template_id: c::ID), required: %w[import_id template_id]),
      c.definition("list_import_rows", c::PAGE.merge(import), required: [ "import_id" ], read: true),
      c.definition("update_import_row", import.merge(row_id: c::ID, values: { type: "object", properties: row, additionalProperties: false }), required: %w[import_id row_id values]),
      c.definition("list_import_mappings", c::PAGE.merge(import), required: [ "import_id" ], read: true),
      c.definition("update_import_mapping", import.merge(mapping_id: c::ID, mappable_id: c::ID, create_when_empty: c::BOOLEAN, value: c::STRING), required: %w[import_id mapping_id]),
      c.definition("preview_import", import, required: [ "import_id" ], read: true),
      c.definition("publish_import", import.merge(preview), required: %w[import_id preview_token]),
      c.definition("validate_backup", import, required: [ "import_id" ], read: true),
      c.definition("restore_backup", import.merge(preview), required: %w[import_id preview_token], destructive: true),
      c.definition("cancel_import", import, required: [ "import_id" ]),
      c.definition("preview_revert_import", import, required: [ "import_id" ], read: true),
      c.definition("revert_import", import.merge(preview), required: %w[import_id preview_token], destructive: true),
      c.definition("delete_import", import, required: [ "import_id" ], destructive: true),
      c.definition("create_import_session", { client_session_id: c::STRING, expected_chunks: { type: "integer", minimum: 1, maximum: 100 } }, required: %w[client_session_id expected_chunks]),
      c.definition("get_import_session", session, required: [ "session_id" ], read: true),
      c.definition("upload_import_chunk", session.merge(upload).merge(sequence: { type: "integer", minimum: 1, maximum: 100 }, client_chunk_id: c::STRING), required: %w[session_id upload_token sequence client_chunk_id]),
      c.definition("preview_import_session", session, required: [ "session_id" ], read: true),
      c.definition("publish_import_session", session.merge(preview), required: %w[session_id preview_token]),
      c.definition("list_statements", c::PAGE.merge(account_id: c::ID), read: true),
      c.definition("get_statement", statement, required: [ "statement_id" ], read: true),
      c.definition("upload_statement", upload.merge(account_id: c::ID), required: [ "upload_token" ]),
      c.definition("update_statement", statement.merge(institution_name_hint: c::STRING, account_name_hint: c::STRING, account_last4_hint: c::STRING, period_start_on: c::DATE, period_end_on: c::DATE, opening_balance: c::MONEY, closing_balance: c::MONEY, currency: c::STRING), required: [ "statement_id" ]),
      c.definition("link_statement", statement.merge(account_id: c::ID), required: %w[statement_id account_id]),
      c.definition("unlink_statement", statement, required: [ "statement_id" ]),
      c.definition("reject_statement", statement, required: [ "statement_id" ]),
      c.definition("delete_statement", statement, required: [ "statement_id" ], destructive: true),
      c.definition("list_documents", c::PAGE, read: true),
      c.definition("get_document", { document_id: c::ID }, required: [ "document_id" ], read: true),
      c.definition("upload_document", upload, required: [ "upload_token" ]),
      c.definition("delete_document", { document_id: c::ID }, required: [ "document_id" ], destructive: true),
      c.definition("list_attachments", { transaction_id: c::ID }.merge(c::PAGE), required: [ "transaction_id" ], read: true),
      c.definition("attach_transaction_file", upload.merge(transaction_id: c::ID), required: %w[upload_token transaction_id]),
      c.definition("delete_transaction_attachment", { transaction_id: c::ID, attachment_id: c::ID }, required: %w[transaction_id attachment_id], destructive: true),
      c.definition("get_file_transfer", file, required: %w[kind id], read: true),
      c.definition("get_upload_channel", {}, read: true),
      c.definition("list_backups", c::PAGE, read: true),
      c.definition("get_backup", backup, required: [ "backup_id" ], read: true),
      c.definition("create_family_backup", {}),
      c.definition("cancel_backup", backup, required: [ "backup_id" ]),
      c.definition("delete_backup", backup, required: [ "backup_id" ], destructive: true)
    ]
    tools
  end
end
