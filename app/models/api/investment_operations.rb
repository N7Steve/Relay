# frozen_string_literal: true

module Api::InvestmentOperations
  def list_trades(args)
    scope = investment_entries("Trade")
    scope = scope.where(account_id: args["account_id"]) if args["account_id"]
    paginate(scope.order(date: :desc, id: :asc), args) { |row| investment_entry_json(row) }
  end

  def get_trade(args)
    investment_entry_json(investment_entry(args["trade_id"], "Trade"))
  end

  def create_trade(args)
    record = account(args.fetch("account_id"), :write)
    invalid!("Account does not support trades") unless record.supports_trades?
    type = args.fetch("type")
    attrs = args.slice("ticker", "type", "transfer_account_id").symbolize_keys.merge(account: record, date: date(args["date"]), currency: market_currency(args.fetch("currency", record.currency)))
    %w[amount qty price fee].each { |key| attrs[key.to_sym] = decimal(args[key]) if args.key?(key) }
    if Trade::CreateForm::SECURITY_TRADE_LABELS.key?(type)
      invalid!("Ticker, positive quantity and price are required") unless attrs[:ticker].present? && attrs[:qty]&.positive? && attrs[:price]&.positive?
    else
      invalid!("Positive amount is required") unless attrs[:amount]&.positive?
    end
    invalid!("Fee must be nonnegative") if attrs[:fee]&.negative?
    model = Trade::CreateForm.new(attrs).create
    invalid!(model.errors.full_messages.to_sentence) unless model&.persisted?
    return transfer_json(model) if model.is_a?(Transfer)
    model.update!(args.slice("name", "notes", "excluded", "import_protected"))
    model.entryable.update!(args.slice("category_id")) if args["category_id"] && model.trade?
    protect_and_sync(model)
    model.trade? ? investment_entry_json(model) : entry_json(model)
  end

  def update_trade(args)
    row = investment_entry(args.fetch("trade_id"), "Trade", :write)
    trade = row.trade
    attrs = args.slice("name", "notes", "currency", "excluded", "import_protected")
    attrs["date"] = date(args["date"]) if args["date"]
    if (args.keys & %w[qty price fee type]).any?
      type = args.fetch("type", trade.qty.negative? ? "sell" : "buy")
      invalid!("Cash activity cannot become a security trade") unless Trade::CreateForm::SECURITY_TRADE_LABELS.key?(type) && !trade.qty.zero?
      qty, price, fee = decimal(args.fetch("qty", trade.qty.abs)), decimal(args.fetch("price", trade.price)), decimal(args.fetch("fee", trade.fee || 0))
      invalid!("Quantity and price must be positive; fee nonnegative") unless qty.positive? && price.positive? && !fee.negative?
      qty = -qty.abs if type.in?(%w[sell sweep_out])
      trade.update!(qty: qty, price: price, fee: fee, investment_activity_label: Trade::CreateForm::SECURITY_TRADE_LABELS.fetch(type))
      attrs["amount"] = qty * price + fee
    elsif args["amount"]
      invalid!("Edit quantity/price for security trades") unless trade.qty.zero?
      value = decimal(args["amount"]).abs
      attrs["amount"] = trade.investment_activity_label.in?(%w[Dividend Interest]) ? -value : value
    end
    trade.update!(category_id: args["category_id"]) if args["category_id"]
    trade.update!(currency: market_currency(args["currency"])) if args["currency"]
    row.update!(attrs)
    protect_and_sync(row)
    investment_entry_json(row.reload)
  end

  def delete_trade(args)
    row = investment_entry(args.fetch("trade_id"), "Trade", :write)
    record = row.account
    row.destroy!
    record.sync_later
    { deleted: true }
  end

  def unlock_trade(args)
    row = investment_entry(args.fetch("trade_id"), "Trade", :write)
    row.unlock_for_sync!
    investment_entry_json(row)
  end

  def list_holdings(args)
    paginate(account(args.fetch("account_id")).current_holdings.order(:id), args) { |row| holding_json(row) }
  end

  def get_holding(args)
    holding_json(investment_holding(args.fetch("holding_id")))
  end

  def update_holding_cost_basis(args)
    row = investment_holding(args.fetch("holding_id"), :write)
    total = decimal(args.fetch("total_cost_basis"))
    invalid!("Nonnegative total basis and positive quantity required") unless !total.negative? && row.qty.positive?
    row.set_manual_cost_basis!(total / row.qty)
    holding_json(row)
  end

  def unlock_holding_cost_basis(args)
    row = investment_holding(args.fetch("holding_id"), :write)
    row.unlock_cost_basis!
    holding_json(row)
  end

  def remap_holding_security(args)
    row = investment_holding(args.fetch("holding_id"), :write)
    parsed = Security.parse_combobox_id(args.fetch("ticker"))
    invalid!("Ticker is required") if parsed[:ticker].blank?
    security = Security::Resolver.new(parsed[:ticker], exchange_operating_mic: parsed[:exchange_operating_mic]).resolve
    row.remap_security!(security)
    record = row.account.reload
    Balance::Materializer.new(record, strategy: record.linked? ? :reverse : :forward, security_ids: [ security.id ]).materialize_balances
    replacement = record.holdings.find_by!(security_id: security.id, date: row.date, currency: row.currency)
    holding_json(replacement)
  end

  def reset_holding_security(args)
    row = investment_holding(args.fetch("holding_id"), :write)
    row.reset_security_to_provider!
    holding_json(row.reload)
  end

  def preview_holding_deletion(args)
    row = investment_holding(args.fetch("holding_id"))
    plan = holding_deletion_plan(row)
    { holding_id: row.id, entry_ids: plan[:entry_ids], count: plan[:entry_ids].size,
      preview_token: process_preview("holding-delete", row.id, plan[:fingerprint]), expires_in: 600 }
  end

  def delete_holding(args)
    row = investment_holding(args.fetch("holding_id"), :write)
    invalid!("Holding deletion is unavailable for this account") unless row.account.can_delete_holdings?
    row.lock!
    plan = holding_deletion_plan(row, lock: true)
    verify_process_preview!(args, "holding-delete", row.id, plan[:fingerprint])
    record = row.account
    row.destroy_holding_and_entries!
    record.sync_later
    { deleted: true }
  end

  def list_valuations(args)
    paginate(account(args.fetch("account_id")).entries.valuations.order(date: :desc, id: :asc), args) { |row| investment_entry_json(row) }
  end

  def preview_reconciliation(args)
    reconciliation_result(account(args.fetch("account_id")).create_reconciliation(balance: decimal(args.fetch("amount")), date: date(args.fetch("date")), dry_run: true))
  end

  def reconcile_account(args)
    reconciliation_result(account(args.fetch("account_id"), :write).create_reconciliation(balance: decimal(args.fetch("amount")), date: date(args.fetch("date"))))
  end

  def update_valuation(args)
    row = investment_entry(args.fetch("valuation_id"), "Valuation", :write)
    result = row.account.update_reconciliation(row, balance: decimal(args.fetch("amount")), date: date(args.fetch("date")))
    reconciliation_result(result)
    row.update!(notes: args["notes"]) if args.key?("notes")
    investment_entry_json(row.reload)
  end

  def delete_valuation(args)
    row = investment_entry(args.fetch("valuation_id"), "Valuation", :write)
    record = row.account
    row.destroy!
    record.sync_later
    { deleted: true }
  end

  def update_managed_portfolio_value(args)
    record = account(args.fetch("account_id"), :write)
    row = record.entries.transactions.find(args["entry_id"]) if args["entry_id"]
    invalid!("Entry is not an anchored managed value") if row && !row.transaction.investment_value_target
    form = Investment::ValueUpdate.new(account: record, entry: row, amount: decimal(args.fetch("amount")), date: date(args.fetch("date")))
    invalid!(form.errors.full_messages.to_sentence) unless form.save
    entry_json(form.entry)
  end

  def list_local_prices(args)
    security = visible_security(args.fetch("security_id"))
    paginate(security.prices.order(date: :desc, id: :asc), args) { |row| financial_json(row.attributes.slice("id", "date", "price", "currency", "security_id")) }
  end

  def set_local_price(args)
    require_market_admin!
    security = Security.find(args.fetch("security_id"))
    value = decimal(args.fetch("price"))
    invalid!("Price must be positive") unless value.positive?
    row = security.prices.find_or_initialize_by(date: date(args.fetch("date")), currency: market_currency(args.fetch("currency")))
    row.update!(price: value)
    financial_json(row.attributes.slice("id", "date", "price", "currency", "security_id"))
  end

  def list_exchange_rates(args)
    paginate(ExchangeRate.where(from_currency: market_currency(args.fetch("from_currency")), to_currency: market_currency(args.fetch("to_currency"))).order(date: :desc, id: :asc), args) { |row| financial_json(row.attributes) }
  end

  def set_exchange_rate(args)
    require_market_admin!
    from, to, rate = market_currency(args.fetch("from_currency")), market_currency(args.fetch("to_currency")), decimal(args.fetch("rate"))
    invalid!("Rate must be positive and currencies different") unless rate.positive? && from != to
    row = ExchangeRate.find_or_initialize_by(from_currency: from, to_currency: to, date: date(args.fetch("date")))
    row.update!(rate: rate)
    financial_json(row.attributes)
  end

  private
    def authorize_investment_arguments!(name, args)
      return unless Mcp::InvestmentCatalog.definitions.any? { |tool| tool[:name] == name }
      permission = Mcp::Catalog.fetch(name)[:annotations][:readOnlyHint] ? :read : :write
      investment_entry(args["trade_id"], "Trade", permission) if args["trade_id"]
      investment_entry(args["valuation_id"], "Valuation", permission) if args["valuation_id"]
      investment_holding(args["holding_id"], permission) if args["holding_id"]
      account(args["transfer_account_id"], :write) if args["transfer_account_id"]
      require_market_admin! if name.in?(%w[set_local_price set_exchange_rate])
    end

    def investment_entries(type)
      family.entries.where(entryable_type: type, account_id: access.accounts.select(:id))
    end

    def investment_entry(id, type, permission = :read)
      row = investment_entries(type).find_by!(entryable_id: id)
      access.require_account!(row.account, permission)
      row
    end

    def investment_holding(id, permission = :read)
      row = family.holdings.where(account_id: access.accounts.select(:id)).find(id)
      access.require_account!(row.account, permission)
      row
    end

    def holding_deletion_plan(row, lock: false)
      entries = row.account.entries.where(entryable: row.account.trades.where(security_id: row.security_id)).order(:id)
      entries = entries.lock if lock
      entries = entries.to_a
      invalid!("Holding deletion is limited to 100 trades") if entries.size > 100
      { entry_ids: entries.map(&:id), fingerprint: process_digest([ row.attributes, entries.map { |item| [ item.attributes, item.trade.attributes ] } ]) }
    end

    def investment_entry_json(row)
      financial_json(row.attributes.slice("id", "date", "name", "notes", "amount", "currency", "account_id", "entryable_id", "excluded", "import_protected")).merge("details" => financial_json(row.entryable.attributes.except("created_at", "updated_at")))
    end

    def holding_json(row)
      financial_json(row.attributes).merge("name" => row.name)
    end

    def reconciliation_result(result)
      invalid!(result.error_message.to_s) unless result.success?
      financial_json(result.to_h)
    end

    def visible_security(id)
      Security.where(id: family.holdings.where(account_id: access.accounts.select(:id)).select(:security_id)).or(Security.where(id: family.trades.joins(:entry).where(entries: { account_id: access.accounts.select(:id) }).select(:security_id))).find(id)
    end

    def require_market_admin!
      raise Api::Access::Forbidden, "Shared market data requires an instance super administrator" unless user.super_admin?
    end

    def market_currency(value)
      Money::Currency.new(value).iso_code
    rescue Money::Currency::UnknownCurrencyError
      invalid!("Unknown currency")
    end
end
