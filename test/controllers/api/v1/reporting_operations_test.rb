# frozen_string_literal: true

require "test_helper"

class Api::V1::ReportingOperationsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @key = ApiKey.create!(user: @user, name: "Reports", scopes: %w[read], source: "web", display_key: "reports_#{SecureRandom.hex(12)}")
    @period = { start_date: Date.current.beginning_of_month.iso8601, end_date: Date.current.iso8601 }
  end

  test "report totals and comparisons match the web domain with accounting exclusions" do
    account = accounts(:depository)
    [ { amount: "-300", shared_expense: false }, { amount: "100", shared_expense: true },
      { amount: "10", forecast_behavior: "exceptional_once" }, { amount: "20", posting_status: "pending" } ].each do |attrs|
      account.entries.create!(name: "Report case", date: Date.current, currency: "USD", amount: attrs.delete(:amount), entryable: Transaction.new(attrs))
    end
    period = Period.custom(start_date: Date.current.beginning_of_month, end_date: Date.current)
    expected = Reports::Activity.new(@user.family, user: @user).totals(period: period)
    invoke("get_activity_report", @period)
    assert_response :success, response.body
    assert_equal expected.income.amount, response.parsed_body.dig("current", "income", "amount").to_d
    assert_equal expected.expenses.amount, response.parsed_body.dig("current", "expenses", "amount").to_d
    assert response.parsed_body.key?("adjusted_savings")
    invoke("get_category_report", @period)
    assert_response :success, response.body
    expected_categories = IncomeStatement.new(@user.family, user: @user).net_category_totals(period: period)
    assert_equal expected_categories.total_net_expense.to_d, response.parsed_body.fetch("total_expenses").to_d
    invoke("get_shared_expenses", @period)
    assert_response :success, response.body
    calculator = SharedExpensesCalculator.new(@user.family, accounts: @user.finance_accounts, transactions: Reports::Activity.new(@user.family, user: @user).cash_transactions)
    assert_equal calculator.calculate_adjusted_expenses(period).amount, response.parsed_body.dig("adjusted_expenses", "amount").to_d
  end

  test "series and net worth preserve server values and currency" do
    invoke("get_report_accounts", per_page: 100)
    assert_response :success
    assert response.parsed_body.fetch("data").all? { |row| row.key?("cash_report_eligible") && row.key?("tax_treatment") }
    invoke("get_net_worth", {})
    assert_response :success, response.body
    expected = BalanceSheet.new(@user.family, user: @user)
    assert_equal expected.net_worth, response.parsed_body.dig("net_worth", "amount").to_d
    invoke("get_net_worth_series", @period)
    assert_response :success, response.body
    assert response.parsed_body.fetch("points").is_a?(Array)
    invoke("get_account_balance_series", @period.merge(account_id: accounts(:depository).id))
    assert_response :success, response.body
    assert_equal "USD", response.parsed_body.fetch("currency")
  end

  test "CSV is bounded paginated and keeps original signed denominations" do
    entry = accounts(:depository).entries.create!(name: "=unsafe", date: Date.current, amount: "-25.75", currency: "USD", entryable: Transaction.new)
    invoke("export_transactions", @period.merge(search: "=unsafe", per_page: 1))
    assert_response :success, response.body
    rows = CSV.parse(response.parsed_body.fetch("csv"), headers: true)
    assert_equal 1, rows.length
    assert_equal "'=unsafe", rows.first["name"]
    assert_equal entry.amount, rows.first["amount"].to_d
    assert_equal "USD", rows.first["currency"]
    assert_equal 1, response.parsed_body.dig("pagination", "total_count")
  end

  test "invalid periods excluded accounts and missing FX fail explicitly" do
    invoke("get_activity_report", @period.merge(start_date: "2026-02-30"))
    assert_response :unprocessable_entity
    invoke("get_category_report", @period.merge(start_date: "2027-01-01", end_date: "2026-01-01"))
    assert_response :unprocessable_entity
    excluded = accounts(:depository)
    excluded.update!(financial_treatment: "tracking")
    invoke("get_activity_report", @period.merge(account_ids: [ excluded.id ]))
    assert_response :unprocessable_entity
    excluded.update!(financial_treatment: "included")
    ExchangeRate.delete_all
    excluded.entries.create!(name: "Missing FX", date: Date.current, amount: "12", currency: "EUR", entryable: Transaction.new)
    invoke("get_activity_report", @period)
    assert_response :unprocessable_entity, response.body
    assert_equal "missing_conversion", response.parsed_body.fetch("code")
  end

  test "reports cannot reveal another family or a shared account excluded from finances" do
    member = users(:family_member)
    @key.update!(user: member)
    own = accounts(:other_asset)
    own.update!(owner: member)
    private_account = accounts(:depository)
    AccountShare.where(user: member, account: private_account).delete_all
    invoke("get_account_balance_series", @period.merge(account_id: private_account.id))
    assert_response :not_found
    invoke("get_activity_report", @period.merge(account_ids: [ private_account.id ]))
    assert_response :unprocessable_entity
  end

  test "forecasts and investment report use the maintained engines" do
    invoke("get_account_forecast", account_id: accounts(:depository).id, horizon_months: 1)
    assert_response :success, response.body
    assert response.parsed_body.fetch("chart").key?("points")
    invoke("get_wealth_forecast", horizon_months: 1)
    assert_response :success, response.body
    assert response.parsed_body.fetch("chart").key?("points")
    invoke("get_investment_report", @period)
    assert_response :success, response.body
    assert response.parsed_body.key?("portfolio_value")
  end

  private
    def invoke(name, args)
      post "/api/v1/actions/#{name}", params: { arguments: args }, headers: { "X-Api-Key" => @key.display_key }, as: :json
    end
end
