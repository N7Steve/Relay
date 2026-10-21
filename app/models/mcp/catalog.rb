# frozen_string_literal: true

class Mcp::Catalog
  STRING = { type: "string", maxLength: 2000 }.freeze
  ID = { type: "string", pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$" }.freeze
  MONEY = { type: "string", pattern: "^-?[0-9]+(\\.[0-9]+)?$", maxLength: 40 }.freeze
  DATE = { type: "string", pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" }.freeze
  BOOLEAN = { type: "boolean" }.freeze
  IDS = { type: "array", items: ID, maxItems: 100, uniqueItems: true }.freeze
  PAGE = { page: { type: "integer", minimum: 1 }, per_page: { type: "integer", minimum: 1, maximum: 100 } }.freeze
  KEY = { type: "string", minLength: 1, maxLength: 128 }.freeze
  TRANSACTION = {
    name: STRING, date: DATE, amount: MONEY, currency: { type: "string", pattern: "^[A-Z]{3}$" }, notes: STRING,
    category_id: { type: [ "string", "null" ] }, merchant_id: { type: [ "string", "null" ] }, tag_ids: IDS,
    excluded: BOOLEAN, import_protected: BOOLEAN, shared_expense: BOOLEAN, posting_status: { type: "string", enum: %w[pending posted] },
    kind: { type: "string", enum: %w[standard funds_movement cc_payment loan_payment investment_contribution transfer_to_excluded transfer_from_excluded] },
    forecast_behavior: { type: "string", enum: %w[normal exceptional_once irregular_recurring] }
  }.freeze
  ACCOUNT = {
    name: STRING, balance: MONEY, currency: { type: "string", pattern: "^[A-Z]{3}$" },
    notes: STRING, institution_name: STRING, institution_domain: STRING,
    subtype: STRING, financial_treatment: { type: "string", enum: Account::FINANCIAL_TREATMENTS }, archived: BOOLEAN,
    enable_category_matcher: BOOLEAN,
    accountable_attributes: { type: "object", additionalProperties: false, properties: {
      subtype: STRING, tax_treatment: { type: "string", enum: %w[taxable tax_deferred tax_exempt] },
      tracking_mode: { type: "string", enum: Investment::TRACKING_MODES }, rate_type: STRING, interest_rate: MONEY,
      term_months: { type: "integer", minimum: 1 }, initial_balance: MONEY, start_date: DATE, down_payment: MONEY,
      insurance_rate: MONEY, insurance_rate_type: STRING, make: STRING, model: STRING, year: { type: "integer" },
      mileage_value: MONEY, mileage_unit: STRING,
      available_credit: MONEY, minimum_payment: MONEY, apr: MONEY, annual_fee: MONEY, expiration_date: DATE,
      year_built: { type: "integer" }, area_unit: STRING, area_value: MONEY,
      address_attributes: { type: "object", additionalProperties: false, properties: {
        line1: STRING, line2: STRING, locality: STRING, region: STRING, country: STRING, postal_code: STRING
      } },
      rate_changes: { type: "array", maxItems: 100, items: { type: "object", additionalProperties: false,
        properties: { effective_date: DATE, rate: MONEY }, required: %w[effective_date rate] } }
    } }
  }.freeze

  def self.definition(name, properties, required: [], read: false, destructive: false, description: nil)
    properties = properties.merge(idempotency_key: KEY) unless read
    {
      name: name, description: description || "#{name.tr('_', ' ').capitalize}. Uses authenticated account permissions and Relay financial rules.",
      inputSchema: { type: "object", properties: properties, required: required + (read ? [] : [ "idempotency_key" ]), additionalProperties: false },
      outputSchema: result_schema(name),
      annotations: { readOnlyHint: read, destructiveHint: destructive, idempotentHint: true, openWorldHint: false }
    }
  end

  def self.result_schema(name)
    account = { type: "object", required: %w[id name balance currency capabilities], properties: {
      id: ID, name: STRING, balance: MONEY, currency: STRING,
      capabilities: { type: "object", required: %w[read annotate write], properties: { read: BOOLEAN, annotate: BOOLEAN, write: BOOLEAN } },
      accountable: { type: "object" }
    } }
    entry = { type: "object", required: %w[id transaction_id account_id amount date currency], properties: {
      id: ID, transaction_id: ID, account_id: ID, amount: MONEY, date: DATE, currency: STRING,
      transaction: { type: "object" }
    } }
    organization = { type: "object", required: %w[id name], properties: { id: ID, name: STRING } }
    if name.start_with?("list_") || name.in?(%w[search_transactions get_report_accounts])
      item = name == "list_accounts" ? account : name == "search_transactions" ? entry : organization
      item = { type: "object", required: %w[id currency start_date editable], properties: { id: ID, currency: STRING, start_date: DATE, editable: BOOLEAN } } if name == "list_budgets"
      item = { type: "object", required: %w[id title status amount currency], properties: { id: ID, title: STRING, status: STRING, amount: MONEY, currency: STRING } } if name == "list_scheduled_payments"
      item = { type: "object", required: %w[id goal_id account_id amount status], properties: { id: ID, goal_id: ID, account_id: ID, amount: MONEY, status: STRING } } if name == "list_goal_pledges"
      item = { type: "object" } if name.in?(%w[list_trades list_holdings list_valuations list_local_prices list_exchange_rates list_rules list_rule_runs list_imports list_import_rows list_import_mappings list_statements list_documents list_attachments list_backups])
      item = { type: "object" } if name.in?(%w[list_members list_invitations list_account_shares list_budget_shares list_sessions list_api_keys list_oauth_grants list_diagnostics list_insights list_bank_connections list_bank_accounts list_syncs list_drive_schedules list_drive_runs list_background_operations])
      item = { type: "object" } if name.in?(%w[list_transfers list_rejected_transfers list_local_securities])
      return { type: "object", required: %w[data pagination], properties: {
        data: { type: "array", items: item, maxItems: 100 },
        pagination: { type: "object", required: %w[page per_page total_count next_page], properties: {
          page: { type: "integer" }, per_page: { type: "integer" }, total_count: { type: "integer" }, next_page: { type: [ "integer", "null" ] }
        } }
      } }
    end
    return account if %w[get_account create_account update_account set_account_status].include?(name)
    return entry if %w[create_transaction update_transaction duplicate_transaction unsplit_transaction protect_transaction unlock_transaction].include?(name)
    return { type: "object", required: %w[parent children], properties: { parent: entry, children: { type: "array", items: entry } } } if name == "split_transaction"
    if %w[create_transfer match_transfer].include?(name)
      return { type: "object", required: %w[id status outflow inflow], properties: { id: ID, status: STRING, outflow: entry, inflow: entry } }
    end
    return organization if name.match?(/\A(?:create|update|merge|replace)_(?:category|categories|merchant|merchants|tag|tags)\z/)
    { type: "object" }
  end

  def self.all
    @all ||= begin
      tools = [
        definition("get_context", {}, read: true),
        definition("list_accounts", PAGE.merge(include_disabled: BOOLEAN), read: true),
        definition("get_account", { account_id: ID }, required: [ "account_id" ], read: true),
        definition("search_transactions", transaction_search_properties, read: true),
        definition("get_cash_flow", { month: DATE, include_sankey: BOOLEAN }, read: true),
        definition("get_operation", { idempotency_key: KEY }, required: [ "idempotency_key" ], read: true),
        definition("get_account_sync", { account_id: ID }, required: [ "account_id" ], read: true),
        definition("create_account", ACCOUNT.merge(accountable_type: { type: "string", enum: Accountable::TYPES }, opening_balance_date: DATE), required: %w[name balance accountable_type]),
        definition("update_account", ACCOUNT.merge(account_id: ID), required: [ "account_id" ]),
        definition("set_account_status", { account_id: ID, active: BOOLEAN, archived: BOOLEAN }, required: [ "account_id" ]),
        definition("set_default_account", { account_id: { type: [ "string", "null" ] } }),
        definition("create_transaction", TRANSACTION.merge(account_id: ID), required: %w[account_id name date amount]),
        definition("update_transaction", TRANSACTION.merge(transaction_id: ID), required: [ "transaction_id" ]),
        definition("delete_transaction", { transaction_id: ID }, required: [ "transaction_id" ], destructive: true),
        definition("split_transaction", { transaction_id: ID, splits: { type: "array", minItems: 2, maxItems: 100, items: {
          type: "object", properties: TRANSACTION.slice(:name, :amount, :category_id, :excluded, :notes, :import_protected), required: %w[name amount], additionalProperties: false } } }, required: %w[transaction_id splits]),
        definition("unsplit_transaction", { transaction_id: ID }, required: [ "transaction_id" ]),
        definition("protect_transaction", { transaction_id: ID, protected: BOOLEAN }, required: %w[transaction_id protected]),
        definition("unlock_transaction", { transaction_id: ID }, required: [ "transaction_id" ]),
        definition("bulk_update_transactions", { transaction_ids: IDS.merge(minItems: 1), attributes: { type: "object", properties: TRANSACTION.slice(:name, :date, :notes, :category_id, :merchant_id, :tag_ids), additionalProperties: false } }, required: %w[transaction_ids attributes]),
        definition("preview_categorization", { transaction_ids: IDS.merge(minItems: 1) }, required: [ "transaction_ids" ], read: true),
        definition("preview_bulk_delete_transactions", { transaction_ids: IDS.merge(minItems: 1) }, required: [ "transaction_ids" ], read: true),
        definition("bulk_delete_transactions", { transaction_ids: IDS.merge(minItems: 1), preview_token: { type: "string", maxLength: 20000 } }, required: %w[transaction_ids preview_token], destructive: true),
        definition("merge_duplicate", { transaction_id: ID }, required: [ "transaction_id" ], destructive: true),
        definition("dismiss_duplicate", { transaction_id: ID }, required: [ "transaction_id" ]),
        definition("duplicate_transaction", { transaction_id: ID, date: DATE }, required: %w[transaction_id date]),
        definition("convert_transaction_to_trade", { transaction_id: ID, security_id: ID, quantity: MONEY, price: MONEY }, required: %w[transaction_id security_id quantity price]),
        definition("create_transfer", { source_account_id: ID, destination_account_id: ID, date: DATE, amount: MONEY, name: STRING,
          exchange_rate: MONEY, category_id: ID, source_fee_amount: MONEY, destination_fee_amount: MONEY, tag_ids: IDS }, required: %w[source_account_id destination_account_id date amount]),
        definition("match_transfer", { outflow_transaction_id: ID, inflow_transaction_id: ID }, required: %w[outflow_transaction_id inflow_transaction_id]),
        definition("update_transfer", { transfer_id: ID, name: STRING, notes: STRING, amount: MONEY, source_fee_amount: MONEY, destination_fee_amount: MONEY, category_id: { type: [ "string", "null" ] }, tag_ids: IDS,
          status: { type: "string", enum: %w[confirmed rejected] } }, required: [ "transfer_id" ]),
        definition("unlink_transfer", { transfer_id: ID }, required: [ "transfer_id" ], destructive: true),
        definition("delete_transfer", { transfer_id: ID }, required: [ "transfer_id" ], destructive: true)
      ]
      { category: { name: STRING, color: STRING, lucide_icon: STRING, parent_id: { type: [ "string", "null" ] } },
        merchant: { name: STRING, color: STRING, website_url: STRING }, tag: { name: STRING, color: STRING } }.each do |kind, attrs|
        tools << definition("list_#{kind.to_s.pluralize}", PAGE, read: true)
        tools << definition("create_#{kind}", attrs, required: [ "name" ])
        tools << definition("update_#{kind}", attrs.merge("#{kind}_id" => ID), required: [ "#{kind}_id" ])
        tools << definition("delete_#{kind}", { "#{kind}_id" => ID }, required: [ "#{kind}_id" ], destructive: true)
        tools << definition("merge_#{kind.to_s.pluralize}", { target_id: ID, source_ids: IDS.merge(minItems: 1) }, required: %w[target_id source_ids], destructive: true)
        tools << definition("replace_#{kind}", { "#{kind}_id" => ID, replacement_id: ID }, required: [ "#{kind}_id", "replacement_id" ], destructive: true) if kind.in?([ :category, :tag ])
      end
      tools += Mcp::ReportingCatalog.definitions + Mcp::PlanningCatalog.definitions + Mcp::InvestmentCatalog.definitions + Mcp::ProcessCatalog.definitions + Mcp::AdministrationCatalog.definitions + Mcp::IntegrationCatalog.definitions + Mcp::ParityCatalog.definitions
      tools.index_by { |tool| tool[:name] }.freeze
    end
  end

  def self.transaction_search_properties
    PAGE.merge(TRANSACTION.slice(:excluded, :import_protected, :category_id, :merchant_id, :tag_ids, :kind, :forecast_behavior, :shared_expense, :posting_status)).merge(
      account_ids: IDS, start_date: DATE, end_date: DATE, min_amount: MONEY, max_amount: MONEY, search: STRING,
      include_split_parents: BOOLEAN, exclude_split_children: BOOLEAN, uncategorized: BOOLEAN, untagged: BOOLEAN,
      type: { type: "string", enum: %w[income expense] })
  end

  def self.fetch(name)
    all.fetch(name) { raise Api::Input::Invalid, "Unknown operation" }
  end

  # Validate a deliberately small, explicit JSON Schema subset. The catalog
  # never loads schemas or Ruby methods supplied by a caller.
  def self.validate!(schema, value, path = "arguments")
    schema = schema.deep_stringify_keys
    types = Array(schema["type"])
    type = case value
    when Hash then "object"
    when Array then "array"
    when String then "string"
    when Integer then "integer"
    when TrueClass, FalseClass then "boolean"
    when NilClass then "null"
    end
    raise Api::Input::Invalid, "#{path} has an invalid type" unless types.include?(type)
    if value.is_a?(Hash)
      properties = schema.fetch("properties", {})
      raise Api::Input::Invalid, "#{path} contains unknown fields" if schema["additionalProperties"] == false && (value.keys - properties.keys).any?
      raise Api::Input::Invalid, "#{path} is missing required fields" if (schema.fetch("required", []) - value.keys).any?
      value.each { |key, item| validate!(properties[key], item, "#{path}.#{key}") if properties[key] }
    elsif value.is_a?(Array)
      raise Api::Input::Invalid, "#{path} has an invalid number of items" unless value.length.between?(schema.fetch("minItems", 0), schema.fetch("maxItems", 100))
      raise Api::Input::Invalid, "#{path} must contain unique items" if schema["uniqueItems"] && value.uniq.length != value.length
      value.each { |item| validate!(schema.fetch("items"), item, path) }
    elsif value.is_a?(String)
      valid = value.length.between?(schema.fetch("minLength", 0), schema.fetch("maxLength", 2000))
      valid &&= Regexp.new("\\A(?:#{schema['pattern'].delete_prefix('^').delete_suffix('$')})\\z").match?(value) if schema["pattern"]
      raise Api::Input::Invalid, "#{path} has an invalid value" unless valid
    elsif value.is_a?(Integer)
      raise Api::Input::Invalid, "#{path} is out of range" unless value.between?(schema.fetch("minimum", -Float::INFINITY), schema.fetch("maximum", Float::INFINITY))
    end
    raise Api::Input::Invalid, "#{path} has an invalid choice" if schema["enum"] && !schema["enum"].include?(value)
  end
end
