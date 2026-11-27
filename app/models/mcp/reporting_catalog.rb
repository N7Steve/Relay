# frozen_string_literal: true

class Mcp::ReportingCatalog
  def self.definitions
    c = Mcp::Catalog
    period = { start_date: c::DATE, end_date: c::DATE }
    filter = period.merge(account_ids: c::IDS)
    breakdown = filter.merge(
      type: { type: "string", enum: %w[expense income] },
      limit: { type: "integer", minimum: 1, maximum: 100 }
    )
    [
      c.definition("get_financial_overview", { months: { type: "integer", minimum: 1, maximum: 12 } }, read: true,
        description: "Start here for financial analysis: single-call executive snapshot with net worth, finance accounts, current month activity and comparison, recent monthly trend (default 3 months), top expense categories, investments, shared expenses, active budgets, goals, agenda summary, and recent insights."),
      c.definition("get_monthly_summary", {
        months: { type: "integer", minimum: 1, maximum: 24 },
        end_month: c::DATE,
        account_ids: c::IDS,
        include_categories: c::BOOLEAN,
        category_id: c::ID
      }, read: true,
        description: "Multi-month time series (1 to 24 months, default 12) of income, expenses, adjusted expenses, net and adjusted savings, savings rates, and managed investment returns, plus completed-month averages. Optionally include top monthly categories or track a specific category_id across months."),
      c.definition("get_report_accounts", c::PAGE, read: true,
        description: "List accessible accounts with their financial_treatment, tax_treatment, and eligibility flags for cash, finance, and investment reports."),
      c.definition("get_activity_report", filter, required: %w[start_date end_date], read: true,
        description: "Income, expenses, net savings, adjusted expenses/savings (accounting for shared expenses), and managed portfolio investment_return for a custom period, compared against the immediately preceding period of equal length."),
      c.definition("get_spending_trend", filter, required: %w[start_date end_date], read: true,
        description: "Cumulative daily spending of a period (at most 92 days) against the previous month at the same day count. Uses authenticated account permissions and Relay financial rules."),
      c.definition("get_category_report", filter, required: %w[start_date end_date], read: true,
        description: "Net income and net expense totals grouped by top-level category (with percentage weights, sorted descending) for a period in family currency. Use this instead of summing search_transactions."),
      c.definition("get_merchant_report", breakdown, required: %w[start_date end_date], read: true,
        description: "Expense and income totals grouped by merchant (with transaction counts, average ticket, and percentage weights, sorted descending) for a period in family currency. Use this instead of paginating search_transactions."),
      c.definition("get_tag_report", breakdown, required: %w[start_date end_date], read: true,
        description: "Expense and income totals grouped by personal tag (with transaction counts and averages, sorted descending) for a period in family currency. Note: multi-tag transactions count under each tag."),
      c.definition("get_shared_expenses", filter, required: %w[start_date end_date], read: true,
        description: "Shared-expense balance/debt, adjusted expenses for the period, and rent income computed by Relay's native SharedExpensesCalculator."),
      c.definition("get_investment_report", filter, required: %w[start_date end_date], read: true,
        description: "Investment statement for a period: portfolio value, cash, holdings, unrealized gains, period return trend, and per-account managed portfolio returns with tax treatment."),
      c.definition("get_net_worth", {}, read: true,
        description: "Current balance sheet snapshot in family currency: net worth, total assets, and total liabilities across finance-eligible accounts."),
      c.definition("get_net_worth_series", period, required: %w[start_date end_date], read: true,
        description: "Historical daily net worth time series in family currency for up to 731 days."),
      c.definition("get_account_balance_series", period.merge(account_id: c::ID, view: { type: "string", enum: %w[balance cash_balance holdings_balance gains] }), required: %w[account_id start_date end_date], read: true,
        description: "Historical daily series for one account in its native currency (up to 731 days): balance, cash_balance, holdings_balance, or gains."),
      c.definition("export_transactions", c.transaction_search_properties, required: %w[start_date end_date], read: true,
        description: "Paginated CSV export of filtered transactions in their original ledger currency and signed amounts (positive = outflow, negative = inflow)."),
      c.definition("get_account_forecast", { account_id: c::ID, horizon_months: { type: "integer", enum: ScheduledPayment::Forecast::HORIZONS } }, required: [ "account_id" ], read: true,
        description: "Projected future balance and monthly savings for a single account over the selected horizon, incorporating history and scheduled Agenda payments."),
      c.definition("get_wealth_forecast", { horizon_months: { type: "integer", enum: ScheduledPayment::WealthForecast::HORIZONS }, include_agenda: c::BOOLEAN }, read: true,
        description: "Projected future net worth and monthly savings across finance accounts over the selected horizon, optionally including scheduled Agenda payments.")
    ]
  end
end
