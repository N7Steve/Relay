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

  # Cumulative daily spending of a period against the month before it, as the
  # dashboard's spending chart. The comparison total stops at the same day count.
  def get_spending_trend(args)
    period = report_period(args, max_days: 92)
    previous = Period.custom(start_date: period.start_date.prev_month, end_date: period.start_date - 1)
    accounts = report_accounts(args, include_tax_advantaged: true)
    statement = IncomeStatement.new(family, user: user, accounts: accounts)
    current, prior = spending_series(statement, period), spending_series(statement, previous)
    comparison = prior[[ current.size, prior.size ].min - 1]
    current_total, comparison_total = current.last.fetch(:amount).to_d, comparison.fetch(:amount).to_d
    report_envelope(period, accounts).merge(
      previous_period: { start_date: previous.start_date.iso8601, end_date: previous.end_date.iso8601 },
      current_total: current_total.to_s("F"), comparison_total: comparison_total.to_s("F"),
      comparison_end_date: comparison.fetch(:date), delta: (current_total - comparison_total).to_s("F"),
      current: current, previous: prior)
  end

  def get_category_report(args)
    period, accounts = report_period(args), report_accounts(args)
    statement = IncomeStatement.new(family, user: user, accounts: accounts)
    categories = statement.net_category_totals(period: period)
    serialize = ->(rows) { rows.sort_by { |row| -row.total.to_d }.map { |row| { category_id: row.category.id, name: row.category.name, amount: row.total.to_d.to_s("F"), weight: row.weight } } }
    report_envelope(period, accounts).merge(income: serialize.call(categories.net_income_categories), expenses: serialize.call(categories.net_expense_categories),
      total_income: categories.total_net_income.to_d.to_s("F"), total_expenses: categories.total_net_expense.to_d.to_s("F"))
  end

  def get_merchant_report(args)
    period, accounts = report_period(args), report_accounts(args)
    limit = args.fetch("limit", 25)
    filter_type = args["type"]
    rows = IncomeStatement.new(family, user: user, accounts: accounts).merchant_totals(period: period)
    expense_rows = filter_type == "income" ? [] : rows.select { |row| row.classification == "expense" }
    income_rows = filter_type == "expense" ? [] : rows.select { |row| row.classification == "income" }
    total_expenses = expense_rows.sum(&:total)
    total_income = income_rows.sum(&:total)
    serialize = ->(list, grand_total) {
      list.first(limit).map do |row|
        {
          merchant_id: row.merchant_id,
          name: row.merchant_name,
          amount: row.total.to_d.to_s("F"),
          transactions_count: row.transactions_count,
          average: (row.total / row.transactions_count).round(2).to_d.to_s("F"),
          weight: grand_total.zero? ? 0.0 : (row.total / grand_total * 100).round(2).to_f
        }
      end
    }
    report_envelope(period, accounts).merge(
      total_expenses: total_expenses.to_d.to_s("F"),
      total_income: total_income.to_d.to_s("F"),
      expenses: serialize.call(expense_rows, total_expenses),
      income: serialize.call(income_rows, total_income),
      limit: limit,
      expenses_truncated: expense_rows.length > limit,
      income_truncated: income_rows.length > limit
    )
  end

  def get_tag_report(args)
    period, accounts = report_period(args), report_accounts(args)
    limit = args.fetch("limit", 25)
    filter_type = args["type"]
    tag_ids = family.personal_tags_for(user).pluck(:id)
    rows = IncomeStatement.new(family, user: user, accounts: accounts).tag_totals(period: period, tag_ids: tag_ids)
    expense_rows = filter_type == "income" ? [] : rows.select { |row| row.classification == "expense" }
    income_rows = filter_type == "expense" ? [] : rows.select { |row| row.classification == "income" }
    serialize = ->(list) {
      list.first(limit).map do |row|
        {
          tag_id: row.tag_id,
          name: row.tag_name,
          amount: row.total.to_d.to_s("F"),
          transactions_count: row.transactions_count,
          average: (row.total / row.transactions_count).round(2).to_d.to_s("F")
        }
      end
    }
    report_envelope(period, accounts).merge(
      expenses: serialize.call(expense_rows),
      income: serialize.call(income_rows),
      limit: limit,
      expenses_truncated: expense_rows.length > limit,
      income_truncated: income_rows.length > limit,
      note: "Transactions with multiple tags are counted under each tag; totals across tags may overlap."
    )
  end

  def get_monthly_summary(args)
    months_count = args.fetch("months", 12)
    end_month = args["end_month"] ? date(args["end_month"]) : Date.current.beginning_of_month
    invalid!("end_month must be the first day of a non-future month") unless end_month.day == 1 && end_month <= Date.current.beginning_of_month
    selected_category = args["category_id"] ? family.categories.find(args["category_id"]) : nil
    include_categories = args.fetch("include_categories", false)

    accounts = report_accounts(args, include_tax_advantaged: true)
    activity = Reports::Activity.new(family, user: user, accounts: accounts)
    shared = SharedExpensesCalculator.new(family, accounts: accounts, transactions: activity.cash_transactions)
    category_statement = (include_categories || selected_category) ? IncomeStatement.new(family, user: user, accounts: report_accounts(args)) : nil

    month_starts = (0...months_count).map { |offset| end_month.prev_month(offset) }.reverse
    today = Date.current
    monthly_rows = month_starts.map do |month_start|
      month_end = [ month_start.end_of_month, today ].min
      period = Period.custom(start_date: month_start, end_date: month_end)
      totals = activity.totals(period: period)
      adjusted = shared.calculate_adjusted_expenses(period)
      income = totals.income.amount
      expenses = totals.expenses.amount
      net_savings = income - expenses
      adjusted_savings = income - adjusted.amount
      row = {
        month: month_start.iso8601,
        start_date: period.start_date.iso8601,
        end_date: period.end_date.iso8601,
        partial: month_end < month_start.end_of_month,
        income: income.to_d.to_s("F"),
        expenses: expenses.to_d.to_s("F"),
        adjusted_expenses: adjusted.amount.to_d.to_s("F"),
        net_savings: net_savings.to_d.to_s("F"),
        adjusted_savings: adjusted_savings.to_d.to_s("F"),
        savings_rate: report_savings_rate(income, net_savings),
        adjusted_savings_rate: report_savings_rate(income, adjusted_savings),
        investment_return: totals.investment_return.amount.to_d.to_s("F")
      }
      if category_statement
        net_categories = category_statement.net_category_totals(period: period)
        if include_categories
          row[:expense_categories] = net_categories.net_expense_categories.sort_by { |cat| -cat.total.to_d }.first(10).map do |cat|
            { category_id: cat.category.id, name: cat.category.name, amount: cat.total.to_d.to_s("F"), weight: cat.weight }
          end
          row[:income_categories] = net_categories.net_income_categories.sort_by { |cat| -cat.total.to_d }.first(10).map do |cat|
            { category_id: cat.category.id, name: cat.category.name, amount: cat.total.to_d.to_s("F"), weight: cat.weight }
          end
        end
        if selected_category
          exp_match = net_categories.net_expense_categories.find { |cat| cat.category.id == selected_category.id }
          inc_match = net_categories.net_income_categories.find { |cat| cat.category.id == selected_category.id }
          row[:category_expense] = (exp_match&.total || 0).to_d.to_s("F")
          row[:category_income] = (inc_match&.total || 0).to_d.to_s("F")
        end
      end
      row
    end

    completed_rows = monthly_rows.reject { |row| row[:partial] }
    avg_source = completed_rows.any? ? completed_rows : monthly_rows
    count = avg_source.length
    avg_income = avg_source.sum { |row| row[:income].to_d } / count
    avg_expenses = avg_source.sum { |row| row[:expenses].to_d } / count
    avg_adjusted_expenses = avg_source.sum { |row| row[:adjusted_expenses].to_d } / count
    avg_net_savings = avg_income - avg_expenses
    avg_adjusted_savings = avg_income - avg_adjusted_expenses

    full_period = Period.custom(start_date: month_starts.first, end_date: [ end_month.end_of_month, today ].min)
    result = report_envelope(full_period, accounts).merge(
      months: monthly_rows,
      averages: {
        months_counted: count,
        excludes_partial_current_month: completed_rows.any? && monthly_rows.any? { |row| row[:partial] },
        income: avg_income.round(2).to_d.to_s("F"),
        expenses: avg_expenses.round(2).to_d.to_s("F"),
        adjusted_expenses: avg_adjusted_expenses.round(2).to_d.to_s("F"),
        net_savings: avg_net_savings.round(2).to_d.to_s("F"),
        adjusted_savings: avg_adjusted_savings.round(2).to_d.to_s("F"),
        savings_rate: report_savings_rate(avg_income, avg_net_savings),
        adjusted_savings_rate: report_savings_rate(avg_income, avg_adjusted_savings)
      }
    )
    result[:category] = { id: selected_category.id, name: selected_category.name } if selected_category
    result
  end

  def get_financial_overview(args)
    months_count = args.fetch("months", 3)
    today = Date.current
    current_month_start = today.beginning_of_month
    current_period = Period.custom(start_date: current_month_start, end_date: today)
    previous_period = Period.custom(start_date: current_month_start - current_period.date_range.count, end_date: current_month_start - 1)

    finance_accounts = report_accounts({}, include_tax_advantaged: true)
    cash_accounts = report_accounts({})
    balance_sheet = BalanceSheet.new(family, user: user)
    activity = Reports::Activity.new(family, user: user, accounts: finance_accounts)
    shared = SharedExpensesCalculator.new(family, accounts: finance_accounts, transactions: activity.cash_transactions)

    current_totals = activity.totals(period: current_period)
    previous_totals = activity.totals(period: previous_period)
    current_adjusted = shared.calculate_adjusted_expenses(current_period)
    current_net_savings = current_totals.income - current_totals.expenses
    current_adjusted_savings = current_totals.income - current_adjusted

    recent_months = (0...months_count).map { |offset| current_month_start.prev_month(offset) }.reverse.map do |month_start|
      month_end = [ month_start.end_of_month, today ].min
      period = Period.custom(start_date: month_start, end_date: month_end)
      totals = activity.totals(period: period)
      adjusted = shared.calculate_adjusted_expenses(period)
      net_savings = totals.income.amount - totals.expenses.amount
      {
        month: month_start.iso8601,
        partial: month_end < month_start.end_of_month,
        income: totals.income.amount.to_d.to_s("F"),
        expenses: totals.expenses.amount.to_d.to_s("F"),
        adjusted_expenses: adjusted.amount.to_d.to_s("F"),
        net_savings: net_savings.to_d.to_s("F"),
        savings_rate: report_savings_rate(totals.income.amount, net_savings)
      }
    end

    categories = IncomeStatement.new(family, user: user, accounts: cash_accounts).net_category_totals(period: current_period)
    top_expense_categories = categories.net_expense_categories.sort_by { |row| -row.total.to_d }.first(10).map do |row|
      { category_id: row.category.id, name: row.category.name, amount: row.total.to_d.to_s("F"), weight: row.weight }
    end

    has_investments = finance_accounts.where(accountable_type: %w[Investment Crypto]).exists?
    investments = if has_investments
      inv = InvestmentStatement.new(family, user: user, accounts: finance_accounts)
      {
        portfolio_value: financial_json(inv.portfolio_value_money),
        cash: financial_json(inv.cash_balance_money),
        holdings: financial_json(inv.holdings_value_money),
        unrealized_gains: financial_json(inv.unrealized_gains_money)
      }
    end

    budgets = visible_budgets.where(start_date: current_month_start).order(:id).limit(5).map { |record| budget_json(record) }
    goals = if user.preview_features_enabled?
      planning_goals.where(state: %w[active paused]).order(:name, :id).limit(10).map do |record|
        {
          id: record.id, name: record.name, state: record.state, status: record.display_status,
          currency: record.currency, balance: record.current_balance.to_d.to_s("F"),
          target_amount: record.target_amount.to_d.to_s("F"), progress_percent: record.progress_percent,
          target_date: record.target_date&.iso8601
        }
      end
    else
      []
    end

    agenda = ScheduledPayment::Agenda.new(family: family, user: user, month: current_month_start.iso8601)
    recent_insights = family.insights.for_product_frontend.visible.ordered.order(:id).limit(5).map { |row| insight_json(row) }

    ordered_accounts = finance_accounts.order(:accountable_type, :name, :id).to_a
    {
      as_of: today.iso8601,
      currency: family.currency,
      net_worth: {
        net_worth: financial_json(balance_sheet.net_worth_money),
        assets: financial_json(balance_sheet.assets.total_money),
        liabilities: financial_json(balance_sheet.liabilities.total_money)
      },
      accounts: {
        count: ordered_accounts.length,
        by_type: ordered_accounts.group_by(&:accountable_type).transform_values(&:length),
        items: ordered_accounts.first(50).map do |record|
          { id: record.id, name: record.name, type: record.accountable_type, balance: record.balance.to_s("F"), currency: record.currency, financial_treatment: record.financial_treatment }
        end
      },
      current_month: {
        period: { start_date: current_period.start_date.iso8601, end_date: current_period.end_date.iso8601 },
        previous_period: { start_date: previous_period.start_date.iso8601, end_date: previous_period.end_date.iso8601 },
        income: financial_json(current_totals.income),
        expenses: financial_json(current_totals.expenses),
        adjusted_expenses: financial_json(current_adjusted),
        net_savings: financial_json(current_net_savings),
        adjusted_savings: financial_json(current_adjusted_savings),
        savings_rate: report_savings_rate(current_totals.income.amount, current_net_savings.amount),
        adjusted_savings_rate: report_savings_rate(current_totals.income.amount, current_adjusted_savings.amount),
        investment_return: financial_json(current_totals.investment_return),
        income_change_percent: report_percentage_change(previous_totals.income, current_totals.income),
        expense_change_percent: report_percentage_change(previous_totals.expenses, current_totals.expenses)
      },
      recent_months: recent_months,
      top_expense_categories: top_expense_categories,
      investments: investments,
      shared_expenses: {
        debt: financial_json(shared.calculate_debt),
        adjusted_expenses: financial_json(current_adjusted),
        rent_income: financial_json(shared.calculate_rent_income(current_period))
      },
      budgets: budgets,
      goals: goals,
      agenda: {
        month: current_month_start.iso8601,
        remaining_expenses: financial_json(agenda.remaining_expenses),
        recurring_monthly_expenses: financial_json(agenda.recurring_monthly_expenses),
        active_count: agenda.active_count,
        pending_count: agenda.pending_count
      },
      recent_insights: recent_insights,
      freshness: report_freshness(finance_accounts)
    }
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

    def spending_series(statement, period)
      daily = statement.daily_expense_series(period: period).index_by(&:date)
      cumulative = BigDecimal("0")
      period.date_range.map do |date|
        cumulative += daily[date]&.total || 0
        { date: date.iso8601, amount: cumulative.to_d.to_s("F") }
      end
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

    def report_savings_rate(income, savings)
      income.positive? ? (savings / income * 100).round(1).to_d.to_s("F") : nil
    end
end
