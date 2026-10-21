# frozen_string_literal: true

require "csv"

module Api::ReportingOperations
  def get_report_accounts(args)
    cash_ids = IncomeStatement.new(family, user: user).eligible_accounts.pluck(:id).to_set
    finance_ids = access.accounts.visible.included_in_reports.merge(Account.included_in_finances_for(user)).pluck(:id).to_set
    paginate(access.accounts.order(:name, :id), args) do |record|
      { id: record.id, name: record.name, currency: record.currency, type: record.accountable_type,
        financial_treatment: record.financial_treatment, tax_treatment: record.tax_treatment,
        cash_report_eligible: cash_ids.include?(record.id), finance_eligible: finance_ids.include?(record.id),
        investment_report_eligible: finance_ids.include?(record.id) && record.accountable_type.in?(%w[Investment Crypto]) }
    end
  end

  def get_activity_report(args)
    period = report_period(args)
    previous = Period.custom(start_date: period.start_date - period.date_range.count, end_date: period.start_date - 1)
    accounts = report_accounts(args, include_tax_advantaged: true)
    activity = Reports::Activity.new(family, user: user, accounts: accounts)
    current, prior = activity.totals(period: period), activity.totals(period: previous)
    shared = SharedExpensesCalculator.new(family, accounts: accounts, transactions: activity.cash_transactions)
    adjusted = shared.calculate_adjusted_expenses(period)
    report_envelope(period, accounts).merge(
      current: financial_json(current.to_h), previous: financial_json(prior.to_h),
      previous_period: { start_date: previous.start_date.iso8601, end_date: previous.end_date.iso8601 },
      net_savings: financial_json(current.income - current.expenses), adjusted_expenses: financial_json(adjusted),
      adjusted_savings: financial_json(current.income - adjusted),
      income_change_percent: report_percentage_change(prior.income, current.income),
      expense_change_percent: report_percentage_change(prior.expenses, current.expenses))
  end

  def get_category_report(args)
    period, accounts = report_period(args), report_accounts(args)
    statement = IncomeStatement.new(family, user: user, accounts: accounts)
    categories = statement.net_category_totals(period: period)
    serialize = ->(rows) { rows.map { |row| { category_id: row.category.id, name: row.category.name, amount: row.total.to_d.to_s("F"), weight: row.weight } } }
    report_envelope(period, accounts).merge(income: serialize.call(categories.net_income_categories), expenses: serialize.call(categories.net_expense_categories),
      total_income: categories.total_net_income.to_d.to_s("F"), total_expenses: categories.total_net_expense.to_d.to_s("F"))
  end

  def get_shared_expenses(args)
    period, accounts = report_period(args), report_accounts(args, include_tax_advantaged: true)
    activity = Reports::Activity.new(family, user: user, accounts: accounts)
    calculator = SharedExpensesCalculator.new(family, accounts: accounts, transactions: activity.cash_transactions)
    report_envelope(period, accounts).merge(debt: financial_json(calculator.calculate_debt),
      adjusted_expenses: financial_json(calculator.calculate_adjusted_expenses(period)), rent_income: financial_json(calculator.calculate_rent_income(period)))
  end

  def get_investment_report(args)
    period, accounts = report_period(args), report_accounts(args, include_tax_advantaged: true)
    statement = InvestmentStatement.new(family, user: user, accounts: accounts)
    managed = statement.roboadvisor_accounts.map do |record|
      { account_id: record.id, tax_treatment: record.tax_treatment,
        period_return: financial_json(statement.roboadvisor_account_period_return(record, period: period)) }
    end
    report_envelope(period, accounts).merge(totals: financial_json(statement.totals(period: period).to_h),
      portfolio_value: financial_json(statement.portfolio_value_money), cash: financial_json(statement.cash_balance_money),
      holdings: financial_json(statement.holdings_value_money), unrealized_gains: financial_json(statement.unrealized_gains_money),
      return_trend: financial_json(statement.period_return_trend(period: period).as_json), managed_accounts: managed)
  end

  def get_net_worth(_args)
    statement = BalanceSheet.new(family, user: user)
    { currency: family.currency, net_worth: financial_json(statement.net_worth_money), assets: financial_json(statement.assets.total_money),
      liabilities: financial_json(statement.liabilities.total_money), freshness: report_freshness(access.accounts) }
  end

  def get_net_worth_series(args)
    period = report_period(args, max_days: 731)
    series = BalanceSheet.new(family, user: user).net_worth_series(period: period)
    report_envelope(period, access.accounts).merge(points: financial_series(series))
  end

  def get_account_balance_series(args)
    period = report_period(args, max_days: 731)
    record = account(args.fetch("account_id"))
    { account_id: record.id, currency: record.currency, points: financial_series(record.balance_series(period: period, view: args.fetch("view", "balance").to_sym)), freshness: report_freshness(access.accounts.where(id: record.id)) }
  end

  def export_transactions(args)
    report_period(args)
    data = search_transactions(args)
    csv = CSV.generate do |rows|
      rows << %w[id account_id date name amount currency notes]
      data[:data].each do |row|
        safe_text = ->(value) { value.to_s.match?(/\A[=+\-@\t\r]/) ? "'#{value}" : value }
        rows << [ row["id"], row["account_id"], row["date"], safe_text.call(row["name"]), row["amount"], row["currency"], safe_text.call(row["notes"]) ]
      end
    end
    { content_type: "text/csv", csv: csv, pagination: data[:pagination], denomination: "original ledger currency; positive amounts are outflows" }
  end

  def get_account_forecast(args)
    record = account(args.fetch("account_id"))
    forecast = ScheduledPayment::Forecast.new(family: family, user: user, account: record, horizon_months: args.fetch("horizon_months", 3))
    forecast_result(forecast).merge(account_id: record.id)
  end

  def get_wealth_forecast(args)
    forecast = ScheduledPayment::WealthForecast.new(family: family, user: user, horizon_months: args.fetch("horizon_months", 3), include_agenda: args.fetch("include_agenda", true))
    forecast_result(forecast)
  end

  private
    def report_period(args, max_days: 3660)
      first, last = date(args.fetch("start_date")), date(args.fetch("end_date"))
      invalid!("Period must be ordered and contain at most #{max_days} days") unless first <= last && (last - first).to_i < max_days
      Period.custom(start_date: first, end_date: last)
    end

    def report_accounts(args, include_tax_advantaged: false)
      scope = access.accounts.visible.included_in_reports.merge(Account.included_in_finances_for(user))
      scope = scope.where.not(id: family.tax_advantaged_account_ids) unless include_tax_advantaged
      if args["account_ids"]
        ids = args["account_ids"]
        invalid!("account_ids contains unavailable or excluded report accounts") unless scope.where(id: ids).count == ids.length
        scope = scope.where(id: ids)
      end
      scope
    end

    def report_envelope(period, accounts)
      { currency: family.currency, period: { start_date: period.start_date.iso8601, end_date: period.end_date.iso8601 }, account_ids: accounts.pluck(:id), freshness: report_freshness(accounts) }
    end

    def report_freshness(accounts)
      latest = Sync.where(syncable_type: "Account", syncable_id: accounts.select(:id)).maximum(:updated_at)
      { generated_at: Time.current.iso8601, latest_account_sync_update: latest&.iso8601,
        recalculating: Sync.where(syncable_type: "Account", syncable_id: accounts.select(:id)).visible.exists? }
    end

    def financial_series(series)
      series.map { |point| { date: point.date.iso8601, value: financial_json(point.value) } }
    end

    def financial_json(value)
      case value
      when Money then { amount: value.amount.to_s("F"), currency: value.currency.iso_code }
      when BigDecimal then value.to_s("F")
      when Date, Time, ActiveSupport::TimeWithZone then value.iso8601
      when Hash then value.transform_values { |item| financial_json(item) }
      when Array then value.map { |item| financial_json(item) }
      else value
      end
    end

    def forecast_result(forecast)
      data = forecast.chart_data
      invalid!("Forecast has missing conversion data") if forecast.conversion_failures.positive?
      { start_date: forecast.start_date.iso8601, end_date: forecast.end_date.iso8601,
        current_balance: financial_json(forecast.current_balance), projected_monthly_savings: financial_json(forecast.projected_monthly_savings),
        history_months: forecast.history_months, scheduled_event_count: forecast.scheduled_event_count, chart: financial_json(data) }
    end

    def report_percentage_change(previous, current)
      previous.zero? ? "0.0" : ((current - previous) / previous * 100).round(1).to_d.to_s("F")
    end
end
