# frozen_string_literal: true

# Domain adapter shared by the daily API and MCP. Identity is supplied by the
# authenticated transport, never by tool arguments. Models own financial effects.
class Api::DailyOperations
  include Api::ReportingOperations, Api::PlanningOperations, Api::InvestmentOperations, Api::ProcessOperations,
    Api::AdministrationOperations, Api::IntegrationOperations, Api::ParityOperations
  attr_reader :access, :user, :family

  def initialize(access:)
    @access = access
    @user = access.user
    @family = user.family
  end

  def call(name, arguments)
    definition = Mcp::Catalog.fetch(name)
    args = arguments.deep_stringify_keys
    Mcp::Catalog.validate!(definition.fetch(:inputSchema), args)
    raise Api::Access::Forbidden, "Read access required" unless access.readable?
    raise Api::Access::Forbidden, "Write scope required" if !definition[:annotations][:readOnlyHint] && !access.writable?

    authorize_arguments!(name, args)
    authorize_planning_arguments!(name, args)
    authorize_investment_arguments!(name, args)
    authorize_process_arguments!(name, args)
    authorize_administration_arguments!(name, args)
    authorize_integration_arguments!(name, args)
    require_insight_authority! if name == "refresh_insights"
    if definition[:annotations][:readOnlyHint]
      public_send(name, args)
    else
      result = Api::Operation.execute(user: user, key: args.fetch("idempotency_key"), operation: name, arguments: args) do
        public_send(name, args)
      end
      account(result.fetch("id")) if name == "create_account"
      result
    end
  rescue Category::Merger::UnauthorizedCategoryError, Merchant::Merger::UnauthorizedMerchantError => error
    raise Api::Input::Invalid, error.message
  rescue AASM::InvalidTransition, Goal::ConsumptionRefused, GoalPledge::NotOpenError, GoalPledge::AlreadyClaimedError, BudgetCategory::InvalidMove => error
    raise Api::Input::Invalid, error.message
  rescue Security::MissingPriceError => error
    raise Api::Input::Invalid, error.message
  rescue ExternalAccess::Disabled, Setting::ValidationError => error
    raise Api::Input::Invalid, error.message
  rescue ImportSession::ConflictError, ImportSession::EnqueueError, Import::MaxRowCountExceededError, SureImport::PreflightError, SureImport::NotPublishableError, SureImport::Upload::Error, AccountStatement::InvalidUploadError, CSV::MalformedCSVError => error
    raise Api::Input::Invalid, error.message
  end

  def get_context(_args)
    { user: { id: user.id, role: user.role }, family: { id: family.id, currency: family.currency, timezone: Time.zone.name },
      scopes: access.scopes, capabilities: { read: access.readable?, write: access.writable?, mcp: Mcp::Configuration.enabled? },
      contracts: { money: "Decimal strings; positive ledger amounts are outflows", dates: "YYYY-MM-DD in family timezone" } }
  end

  def list_accounts(args)
    scope = access.accounts.where.not(status: "pending_deletion")
    scope = scope.visible unless args["include_disabled"]
    paginate(scope.order(:name, :id), args) { |account| account_json(account) }
  end

  def get_account(args)
    account_json(account(args.fetch("account_id")))
  end

  def search_transactions(args)
    scope = entries
    scope = scope.where(account_id: args["account_ids"]) if args["account_ids"]
    scope = scope.where("entries.date >= ?", date(args["start_date"])) if args["start_date"]
    scope = scope.where("entries.date <= ?", date(args["end_date"])) if args["end_date"]
    scope = scope.where("entries.amount >= ?", decimal(args["min_amount"])) if args["min_amount"]
    scope = scope.where("entries.amount <= ?", decimal(args["max_amount"])) if args["max_amount"]
    if args["search"]
      scope = scope.where("entries.name ILIKE ? OR entries.notes ILIKE ?", *Array.new(2, "%#{Entry.sanitize_sql_like(args['search'])}%"))
    end
    %w[excluded import_protected].each { |field| scope = scope.where(field => args[field]) if args.key?(field) }
    scope = scope.where(parent_entry_id: nil) if args["exclude_split_children"]
    scope = scope.excluding_split_parents unless args["include_split_parents"]
    scope = scope.joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
    scope = scope.where("entries.amount < 0") if args["type"] == "income"
    scope = scope.where("entries.amount > 0") if args["type"] == "expense"
    scope = scope.where(transactions: { category_id: nil }) if args["uncategorized"]
    scope = scope.where.not(entryable_id: Tagging.where(taggable_type: "Transaction").select(:taggable_id)) if args["untagged"]
    %w[category_id merchant_id kind forecast_behavior shared_expense].each do |field|
      scope = scope.where(transactions: { field => args[field] }) if args.key?(field)
    end
    scope = scope.where(entryable_id: Tagging.where(tag_id: args["tag_ids"], taggable_type: "Transaction").select(:taggable_id)) if args["tag_ids"]
    paginate(scope.order(date: :desc, id: :desc).includes(:entryable), args) { |entry| entry_json(entry) }
  end

  def get_cash_flow(args)
    month = args["month"] ? date(args["month"]) : Date.current.beginning_of_month
    invalid!("month must be a non-future first day") unless month.day == 1 && month <= Date.current
    IncomeStatement::CashFlow.new(IncomeStatement.new(family, user: user), month: month, as_of: Date.current, include_sankey: args.fetch("include_sankey", false)).as_json
  end

  def get_operation(args)
    operation = Api::Operation.find_by!(user: user, key: args.fetch("idempotency_key"))
    # Results can include records whose sharing changed after execution.
    { id: operation.id, status: "completed", completed_at: operation.created_at.iso8601 }
  end

  def get_account_sync(args)
    record = account(args.fetch("account_id"))
    sync = record.latest_sync_record
    { account_id: record.id, syncing: record.syncing?, latest: sync&.as_json(only: %w[id status created_at updated_at]) }
  end

  def create_account(args)
    attributes = args.except("idempotency_key", "opening_balance_date").symbolize_keys
    attributes[:owner] = user
    attributes[:balance] = decimal(attributes[:balance])
    attributes[:currency] ||= family.currency
    invalid!("Unsupported account type") unless Accountable::TYPES.include?(attributes[:accountable_type])
    validate_accountable_attributes!(attributes[:accountable_type], args["accountable_attributes"])
    record = family.accounts.create_and_sync(attributes, opening_balance_date: args["opening_balance_date"] ? date(args["opening_balance_date"]) : 2.years.ago.to_date)
    record.lock_saved_attributes!
    account_json(record)
  end

  def update_account(args)
    record = account(args.fetch("account_id"), :write)
    attributes = args.except("account_id", "idempotency_key", "balance").symbolize_keys
    validate_accountable_attributes!(record.accountable_type, args["accountable_attributes"])
    if args.key?("balance")
      result = record.set_current_balance(decimal(args["balance"]))
      invalid!(result.error.to_s) unless result.success?
    end
    record.update!(attributes)
    record.lock_saved_attributes!
    record.sync_later
    account_json(record)
  end

  def set_account_status(args)
    record = account(args.fetch("account_id"), :write)
    args["active"] ? record.enable! : record.disable! if args.key?("active")
    record.update!(archived: args["archived"]) if args.key?("archived")
    account_json(record)
  end

  def set_default_account(args)
    record = account(args["account_id"]) if args["account_id"]
    invalid!("Account is not eligible as transaction default") if record && !record.eligible_for_transaction_default?
    user.update!(default_account: record)
    { account_id: record&.id }
  end

  def create_transaction(args)
    record = account(args.fetch("account_id"), :write)
    attributes = transaction_attributes(args)
    attributes[:currency] ||= record.currency
    entry = record.entries.create!(attributes.merge(entryable: Transaction.new(transaction_fields(args))))
    protect_and_sync(entry)
    entry_json(entry)
  end

  def update_transaction(args)
    entry = transaction_entry(args.fetch("transaction_id"), :annotate)
    financial = (args.keys - %w[transaction_id idempotency_key category_id merchant_id tag_ids notes]).any?
    access.require_account!(entry.account, :write) if financial
    invalid!("Use the split editor for split children") if entry.split_child?
    if entry.split_parent? && (args.keys & %w[amount date currency excluded]).any?
      invalid!("Split parent financial fields require the split editor")
    end
    if entry.transaction.transfer && financial
      invalid!("Use update_transfer for paired financial movements")
    end
    entry.update!(transaction_attributes(args).merge(entryable_attributes: transaction_fields(args).merge(id: entry.entryable_id)))
    entry.lock_saved_attributes!
    entry.transaction.lock_attr!(:tag_ids) if args.key?("tag_ids")
    entry.mark_user_modified! if financial
    entry.sync_account_later
    entry_json(entry)
  end

  def delete_transaction(args)
    entry = transaction_entry(args.fetch("transaction_id"), :write)
    transfer = entry.transaction.transfer
    related_accounts = [ entry.account ]
    if transfer
      authorize_transfer!(transfer)
      related_accounts += [ transfer.from_account, transfer.to_account ] + transfer.fee_transactions.map { |transaction| transaction.entry.account }
      transfer.destroy!
    end
    invalid!("Split children cannot be deleted individually") if entry.split_child?
    entry.destroy!
    related_accounts.uniq(&:id).each(&:sync_later)
    { deleted: true }
  end

  def split_transaction(args)
    entry = transaction_entry(args.fetch("transaction_id"), :write)
    Entry.transaction do
      entry.lock!
      invalid!("Transaction cannot be split") unless entry.transaction.splittable? || entry.split_parent?
      entry.unsplit! if entry.split_parent?
      rows = args.fetch("splits").map do |row|
        references!(row)
        row.symbolize_keys.merge(amount: decimal(row.fetch("amount")))
      end
      entry.split!(rows)
    end
    entry.sync_account_later
    { parent: entry_json(entry.reload), children: Entry.where(parent_entry_id: entry.id).map { |child| entry_json(child) } }
  end

  def unsplit_transaction(args)
    entry = transaction_entry(args.fetch("transaction_id"), :write)
    Entry.transaction do
      entry.lock!
      invalid!("Transaction is not a split parent") unless entry.split_parent?
      entry.unsplit!
    end
    entry.sync_account_later
    entry_json(entry.reload)
  end

  def protect_transaction(args)
    entry = transaction_entry(args.fetch("transaction_id"), :write)
    entry.update!(import_protected: args.fetch("protected"))
    entry_json(entry)
  end

  def unlock_transaction(args)
    entry = transaction_entry(args.fetch("transaction_id"), :write)
    entry.unlock_for_sync!
    entry_json(entry)
  end

  def bulk_update_transactions(args)
    selected = args.fetch("transaction_ids").map { |id| transaction_entry(id, :annotate) }
    attrs = args.fetch("attributes")
    references!(attrs)
    selected.each do |entry|
      invalid!("Bulk updates exclude split parents, children and transfers") if entry.split_parent? || entry.split_child? || entry.transaction.transfer
      update_transaction(attrs.merge("transaction_id" => entry.entryable_id))
    end
    { updated: selected.length }
  end

  def preview_categorization(args)
    raise Api::Access::Forbidden, "Local categorization needs complete account visibility" unless access.complete_account_visibility?
    categorizer = Family::BayesCategorizer.new(family)
    suggestions = args.fetch("transaction_ids").filter_map do |id|
      entry = transaction_entry(id, :read)
      prediction = categorizer.classify(entry.transaction)
      { transaction_id: id, category_id: prediction.first, confidence: prediction.last } if prediction
    end
    { suggestions: suggestions, training_ready: categorizer.enough_training_data? }
  end

  def preview_bulk_delete_transactions(args)
    plan = bulk_delete_plan(args.fetch("transaction_ids"))
    token = bulk_delete_verifier.generate({ "user_id" => user.id, "transaction_ids" => args["transaction_ids"].sort,
      "fingerprint" => plan[:fingerprint] }, expires_in: 10.minutes, purpose: "daily_bulk_delete")
    { preview_token: token, expires_in_seconds: 600, movement_count: plan[:entries].length,
      transfer_count: plan[:transfers].length, movements: plan[:entries].map { |entry| entry_json(entry) } }
  end

  def bulk_delete_transactions(args)
    preview = bulk_delete_verifier.verified(args.fetch("preview_token"), purpose: "daily_bulk_delete")
    invalid!("Preview is missing, expired or belongs to another request") unless preview && preview["user_id"] == user.id && preview["transaction_ids"] == args["transaction_ids"].sort
    plan = bulk_delete_plan(args.fetch("transaction_ids"))
    Entry.where(id: plan[:entries].map(&:id)).order(:id).lock.load
    Transfer.where(id: plan[:transfers].map(&:id)).order(:id).lock.load
    plan = ActiveRecord::Base.uncached { bulk_delete_plan(args.fetch("transaction_ids")) }
    invalid!("Movements changed since preview; request a new preview") unless plan[:fingerprint] == preview["fingerprint"]
    accounts = plan[:entries].map(&:account).uniq(&:id)
    plan[:transfers].each(&:destroy!)
    plan[:entries].reject(&:split_child?).each { |entry| entry.destroy! if Entry.exists?(entry.id) }
    accounts.each(&:sync_later)
    { deleted_movements: plan[:entries].length, deleted_transfers: plan[:transfers].length }
  end

  def merge_duplicate(args)
    entry = transaction_entry(args.fetch("transaction_id"), :write)
    invalid!("Duplicate merge failed") unless entry.transaction.merge_with_duplicate!
    { merged: true }
  end

  def dismiss_duplicate(args)
    entry = transaction_entry(args.fetch("transaction_id"), :write)
    invalid!("Duplicate dismissal failed") unless entry.transaction.dismiss_duplicate_suggestion!
    { dismissed: true }
  end

  def duplicate_transaction(args)
    source = transaction_entry(args.fetch("transaction_id"), :read)
    access.require_account!(source.account, :write)
    invalid!("Use create_transfer to duplicate paired transfers") if source.transaction.transfer
    create_transaction(source.attributes.slice("name", "currency", "notes").merge(
      "account_id" => source.account_id, "amount" => source.amount.to_s("F"), "date" => args.fetch("date"),
      "category_id" => source.transaction.category_id, "merchant_id" => source.transaction.merchant_id,
      "tag_ids" => source.transaction.tag_ids, "shared_expense" => source.transaction.shared_expense))
  end

  def convert_transaction_to_trade(args)
    entry = transaction_entry(args.fetch("transaction_id"), :write)
    invalid!("Requires an unsplit, unpaired investment transaction") unless entry.account.investment? && !entry.excluded? && !entry.split_child? && !entry.split_parent? && !entry.transaction.transfer
    security = Security.find(args.fetch("security_id"))
    qty, price = decimal(args.fetch("quantity")), decimal(args.fetch("price"))
    invalid!("quantity and price must be positive") unless qty.positive? && price.positive?
    sell = entry.amount.negative?
    trade = entry.account.entries.create!(name: Trade.build_name(sell ? "sell" : "buy", qty, security.ticker), date: entry.date,
      amount: qty * price * (sell ? -1 : 1), currency: entry.currency, notes: entry.notes,
      entryable: Trade.new(security: security, qty: qty * (sell ? -1 : 1), price: price, currency: entry.currency, investment_activity_label: sell ? "Sell" : "Buy"))
    protect_and_sync(trade)
    entry.update!(excluded: true)
    { trade_id: trade.entryable_id, entry_id: trade.id, original_transaction_id: entry.entryable_id }
  end

  def create_transfer(args)
    attrs = args.except("idempotency_key").symbolize_keys
    attrs[:date] = date(args.fetch("date"))
    %i[amount exchange_rate source_fee_amount destination_fee_amount].each { |key| attrs[key] = decimal(attrs[key]) if attrs[key] }
    invalid!("amount must be positive") unless attrs[:amount].positive?
    invalid!("exchange_rate must be positive") if attrs[:exchange_rate] && !attrs[:exchange_rate].positive?
    invalid!("Fees must be non-negative") if %i[source_fee_amount destination_fee_amount].any? { |key| attrs[key]&.negative? }
    transfer = Transfer::Creator.new(family: family, **attrs).create
    transfer_json(transfer)
  end

  def match_transfer(args)
    outflow = transaction_entry(args.fetch("outflow_transaction_id"), :write)
    inflow = transaction_entry(args.fetch("inflow_transaction_id"), :write)
    [ outflow, inflow ].each do |entry|
      invalid!("Split or paired transactions cannot be matched") if entry.split_child? || entry.split_parent? || entry.transaction.transfer
    end
    transfer = Transfer.create!(outflow_transaction: outflow.transaction, inflow_transaction: inflow.transaction, status: "confirmed")
    transfer.reclassify_transactions!
    if transfer.outflow_transaction.kind == "investment_contribution" && transfer.outflow_transaction.category_id.blank?
      transfer.outflow_transaction.update!(category: transfer.to_account.family.investment_contributions_category)
    end
    transfer.sync_account_later
    transfer_json(transfer)
  end

  def update_transfer(args)
    transfer = find_transfer(args.fetch("transfer_id"))
    if args["status"] == "rejected"
      transfer.reject!
      transfer.sync_account_later
      return { rejected: true }
    end
    transfer.confirm! if args["status"] == "confirmed"
    if args["amount"]
      amount = decimal(args["amount"])
      invalid!("amount must be positive") unless amount.positive?
      converted = Money.new(amount, transfer.from_account.currency).exchange_to(transfer.to_account.currency, date: transfer.date).amount
      transfer.outflow_transaction.entry.update!(amount: amount, user_modified: true)
      transfer.inflow_transaction.entry.update!(amount: -converted, user_modified: true)
    end
    update_transfer_fees!(transfer, args)
    transfer.update!(notes: args["notes"]) if args.key?("notes")
    [ transfer.outflow_transaction, transfer.inflow_transaction ].each do |transaction|
      attrs = args.slice("category_id", "tag_ids")
      invalid!("Managed transfers cannot be recategorized") if !transfer.categorizable? && attrs.key?("category_id")
      transaction.update!(attrs)
      transaction.entry.update!(name: args["name"], user_modified: true) if args["name"] && transfer.categorizable?
      transaction.entry.lock_saved_attributes!
    end
    transfer.sync_account_later
    transfer.save!
    transfer_json(transfer)
  end

  def unlink_transfer(args)
    transfer = find_transfer(args.fetch("transfer_id"))
    transfer.destroy!
    transfer.sync_account_later
    { unlinked: true, movements_deleted: false }
  end

  def delete_transfer(args)
    transfer = find_transfer(args.fetch("transfer_id"))
    movements = [ transfer.outflow_transaction.entry, transfer.inflow_transaction.entry ]
    transfer.destroy!
    movements.each { |entry| entry.destroy!; entry.sync_account_later }
    { deleted: true, movements_deleted: true }
  end

  %w[category merchant tag].each do |kind|
    define_method("list_#{kind.pluralize}") do |args|
      paginate(organization_scope(kind).order(:name, :id), args) { |record| organization_json(record) }
    end
    define_method("create_#{kind}") do |args|
      attrs = args.except("idempotency_key")
      record = case kind
      when "category" then family.categories.create!(attrs.reverse_merge("color" => Category::COLORS.first, "lucide_icon" => "shapes"))
      when "merchant" then family.merchants.create!(attrs)
      when "tag" then family.personal_tags_for(user).create!(attrs.reverse_merge("color" => Tag::COLORS.first).merge("user" => user))
      end
      organization_json(record)
    end
    define_method("update_#{kind}") do |args|
      record = organization_scope(kind).find(args.fetch("#{kind}_id"))
      attrs = args.except("idempotency_key", "#{kind}_id")
      if kind == "merchant"
        result = Merchant::Customizer.new(family: family, merchant: record, attributes: attrs.symbolize_keys).call
        invalid!(result.merchant.errors.full_messages.join(", ")) unless result.success?
        record = result.merchant
      else
        record.update!(attrs)
      end
      organization_json(record)
    end
    define_method("delete_#{kind}") do |args|
      record = organization_scope(kind).find(args.fetch("#{kind}_id"))
      if record.is_a?(ProviderMerchant)
        record.unlink_from_family(family)
      else
        record.destroy!
      end
      { deleted: true }
    end
    if kind.in?(%w[category tag])
      define_method("replace_#{kind}") do |args|
        scope = organization_scope(kind)
        source, target = scope.find(args.fetch("#{kind}_id")), scope.find(args.fetch("replacement_id"))
        invalid!("Replacement must differ from source") if source == target
        source.replace_and_destroy!(target)
        organization_json(target)
      end
    end
    define_method("merge_#{kind.pluralize}") do |args|
      scope = organization_scope(kind)
      target = scope.find(args.fetch("target_id"))
      sources = args.fetch("source_ids").map { |id| scope.find(id) }
      invalid!("Target must differ from every source") if sources.include?(target)
      case kind
      when "category"
        Category::Merger.new(family: family, target_category: target, source_categories: sources).merge!
      when "merchant"
        Merchant::Merger.new(family: family, target_merchant: target, source_merchants: sources).merge!
      when "tag"
        sources.each { |source| source.replace_and_destroy!(target) }
      end
      organization_json(target)
    end
  end

  private
    def authorize_arguments!(name, args)
      if args["currency"] && !Money::Currency.all.key?(args["currency"].downcase)
        invalid!("Unknown currency")
      end
      # Re-evaluated before replaying an idempotent response as well as executing.
      if name.match?(/\A(?:create|update|delete|merge|replace)_(?:category|categories|merchant|merchants)\z/)
        raise Api::Access::Forbidden, "Family-wide organization requires an administrator with complete account access" unless access.family_admin? && access.complete_account_visibility?
      end
      references!(args)
      account(args["account_id"], Mcp::Catalog.fetch(name)[:annotations][:readOnlyHint] || name.in?(%w[set_default_account set_finance_inclusion]) ? :read : :write) if args["account_id"]
      %w[source_account_id destination_account_id].each { |key| account(args[key], :write) if args[key] }
      permission = Mcp::Catalog.fetch(name)[:annotations][:readOnlyHint] ? :read : name.in?(%w[update_transaction attach_transaction_file]) ? :annotate : :write
      %w[transaction_id outflow_transaction_id inflow_transaction_id].each { |key| transaction_entry(args[key], permission) if args[key] }
      if name == "update_transaction" && (args.keys - %w[transaction_id idempotency_key category_id merchant_id tag_ids notes]).any?
        transaction_entry(args.fetch("transaction_id"), :write)
      end
      if name == "update_transaction" && args.key?("category_id")
        transfer = transaction_entry(args.fetch("transaction_id"), :annotate).transaction.transfer
        authorize_transfer!(transfer) if transfer
      end
      if args["transfer_id"]
        name == "get_transfer" ? readable_transfers.find(args["transfer_id"]) : find_transfer(args["transfer_id"])
      end
      if name.in?(%w[bulk_update_transactions preview_bulk_delete_transactions bulk_delete_transactions])
        args.fetch("transaction_ids").each { |id| transaction_entry(id, :write) }
      end
    end

    def account(id, permission = :read)
      raise ActiveRecord::RecordNotFound unless UuidFormat.valid?(id)
      record = access.accounts.find(id)
      access.require_account!(record, permission)
      record
    end

    def entries
      family.entries.where(account_id: access.accounts.select(:id), entryable_type: "Transaction")
    end

    def transaction_entry(id, permission)
      entry = entries.find_by!(entryable_id: id)
      access.require_account!(entry.account, permission)
      entry
    end

    def find_transfer(id)
      # Scope before loading so another family's existence is not disclosed.
      transfer = Transfer.where(outflow_transaction_id: entries.select(:entryable_id)).find(id)
      authorize_transfer!(transfer)
      transfer
    end

    def authorize_transfer!(transfer)
      [ transfer.from_account, transfer.to_account ].each { |record| access.require_account!(record, :write) }
      transfer.fee_transactions.each { |transaction| access.require_account!(transaction.entry.account, :write) }
    end

    def transaction_attributes(args)
      attributes = args.slice("name", "notes", "currency", "excluded", "import_protected").symbolize_keys
      attributes[:amount] = decimal(args["amount"]) if args.key?("amount")
      attributes[:date] = date(args["date"]) if args.key?("date")
      attributes
    end

    def transaction_fields(args)
      args.slice("category_id", "merchant_id", "tag_ids", "kind", "forecast_behavior", "shared_expense").symbolize_keys
    end

    def validate_accountable_attributes!(type, attributes)
      return unless attributes
      model = Accountable.from_type(type).new
      allowed = model.attribute_names - %w[id created_at updated_at]
      allowed << "rate_changes" if type == "Loan"
      allowed << "address_attributes" if type == "Property"
      invalid!("Attributes do not belong to #{type}") if (attributes.keys - allowed).any?
    end

    def update_transfer_fees!(transfer, args)
      { "source_fee_amount" => transfer.from_account, "destination_fee_amount" => transfer.to_account }.each do |key, record|
        next unless args.key?(key)
        value = decimal(args[key])
        invalid!("Fees must be non-negative") if value.negative?
        transaction = transfer.fee_transactions.joins(:entry).find_by(entries: { account_id: record.id })
        if transaction
          value.zero? ? transaction.entry.destroy! : transaction.entry.update!(amount: value)
        elsif value.positive?
          category = family.categories.find_or_create_by!(name: I18n.t("models.category.defaults.fees"))
          entry = record.entries.create!(name: "Transfer fee — #{transfer.name}", amount: value, currency: record.currency, date: transfer.date,
            entryable: Transaction.new(category: category, kind: "standard", fee_transfer: transfer))
          protect_and_sync(entry)
        end
      end
    end

    def bulk_delete_verifier
      Rails.application.message_verifier("api_daily_bulk_delete")
    end

    def bulk_delete_plan(ids)
      selected = ids.map { |id| transaction_entry(id, :write) }
      invalid!("Split children must be removed through their parent") if selected.any?(&:split_child?)
      transfers = selected.filter_map { |entry| entry.transaction.transfer }.uniq(&:id)
      transfers.each { |transfer| authorize_transfer!(transfer) }
      all_entries = (selected + transfers.flat_map { |transfer| [ transfer.outflow_transaction.entry, transfer.inflow_transaction.entry ] + transfer.fee_transactions.map(&:entry) }).uniq(&:id)
      all_entries += all_entries.flat_map { |entry| entry.child_entries.to_a }
      all_entries = all_entries.uniq(&:id).sort_by(&:id)
      invalid!("A bulk deletion is limited to 100 movements including children and transfer fees") if all_entries.length > 100
      invalid!("Scheduled movements must be removed through their schedule") if all_entries.any?(&:from_scheduled_payment?)
      fingerprint = Digest::SHA256.hexdigest(JSON.generate([
        all_entries.map { |entry| [ entry.attributes, entry.transaction.attributes, entry.transaction.tag_ids.sort ] },
        transfers.sort_by(&:id).map(&:attributes)
      ]))
      { entries: all_entries, transfers: transfers, fingerprint: fingerprint }
    end

    def references!(args)
      { "category_id" => family.categories, "parent_id" => family.categories,
        "merchant_id" => family.available_merchants_for(user), "tag_ids" => family.personal_tags_for(user) }.each do |key, scope|
        next unless args[key]
        ids = Array(args[key]).uniq
        invalid!("#{key} contains unavailable references") unless ids.all? { |id| UuidFormat.valid?(id) } && scope.where(id: ids).count == ids.length
      end
    end

    def protect_and_sync(entry)
      entry.lock_saved_attributes!
      entry.mark_user_modified!
      entry.sync_account_later
    end

    def organization_scope(kind)
      case kind
      when "category" then family.categories
      when "tag" then family.personal_tags_for(user)
      when "merchant" then family.available_merchants_for(user)
      end
    end

    def organization_json(record)
      record.as_json(only: %w[id name color parent_id lucide_icon website_url type])
    end

    def account_json(record)
      record.as_json(only: %w[id name currency accountable_type status archived financial_treatment notes institution_name institution_domain]).merge(
        "balance" => record.balance.to_s("F"), "capabilities" => access.account_capabilities(record),
        "accountable" => record.accountable.as_json(except: %w[id created_at updated_at]))
    end

    def entry_json(entry)
      entry.as_json(only: %w[id name date currency notes excluded import_protected parent_entry_id]).merge(
        "transaction_id" => entry.entryable_id, "account_id" => entry.account_id,
        "amount" => entry.amount.to_s("F"), "protection" => entry.protection_reason,
        "transaction" => entry.transaction.as_json(only: %w[category_id merchant_id kind forecast_behavior shared_expense]).merge("tag_ids" => entry.transaction.tag_ids))
    end

    def transfer_json(transfer)
      { id: transfer.id, status: transfer.status, outflow: entry_json(transfer.outflow_transaction.entry), inflow: entry_json(transfer.inflow_transaction.entry) }
    end

    def paginate(scope, args)
      page, limit = args.fetch("page", 1), args.fetch("per_page", 25)
      count = scope.count
      { data: scope.offset((page - 1) * limit).limit(limit).map { |record| yield record },
        pagination: { page: page, per_page: limit, total_count: count, next_page: page * limit < count ? page + 1 : nil } }
    end

    def date(value)
      Api::Input.date(value, name: "date")
    end

    def decimal(value)
      Api::Input.decimal(value, name: "amount")
    end

    def invalid!(message)
      raise Api::Input::Invalid, message
    end
end
