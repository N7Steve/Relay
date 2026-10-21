# frozen_string_literal: true

class Mcp::ReportingCatalog
  def self.definitions
    c = Mcp::Catalog
    period = { start_date: c::DATE, end_date: c::DATE }
    filter = period.merge(account_ids: c::IDS)
    [
      c.definition("get_report_accounts", c::PAGE, read: true),
      c.definition("get_activity_report", filter, required: %w[start_date end_date], read: true),
      c.definition("get_category_report", filter, required: %w[start_date end_date], read: true),
      c.definition("get_shared_expenses", filter, required: %w[start_date end_date], read: true),
      c.definition("get_investment_report", filter, required: %w[start_date end_date], read: true),
      c.definition("get_net_worth", {}, read: true),
      c.definition("get_net_worth_series", period, required: %w[start_date end_date], read: true),
      c.definition("get_account_balance_series", period.merge(account_id: c::ID, view: { type: "string", enum: %w[balance cash_balance holdings_balance gains] }), required: %w[account_id start_date end_date], read: true),
      c.definition("export_transactions", c.transaction_search_properties, required: %w[start_date end_date], read: true),
      c.definition("get_account_forecast", { account_id: c::ID, horizon_months: { type: "integer", enum: ScheduledPayment::Forecast::HORIZONS } }, required: [ "account_id" ], read: true),
      c.definition("get_wealth_forecast", { horizon_months: { type: "integer", enum: ScheduledPayment::WealthForecast::HORIZONS }, include_agenda: c::BOOLEAN }, read: true)
    ]
  end
end
