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

  test "spending trend accumulates spending against the previous month at the same day count" do
    user = users(:empty)
    @key.update!(user: user)
    account = user.family.accounts.create!(name: "Cash", balance: 0, currency: "USD", accountable: Depository.new)
    portfolio = user.family.accounts.create!(name: "Managed", balance: 0, currency: "USD", accountable: Investment.new(subtype: "roboadvisor"))
    { Date.new(2026, 2, 3) => 40, Date.new(2026, 2, 20) => 60, Date.new(2026, 3, 2) => 25, Date.new(2026, 3, 4) => -100 }.each do |date, amount|
      account.entries.create!(name: "Spending case", date: date, amount: amount, currency: "USD", entryable: Transaction.new)
    end
    portfolio.entries.create!(name: "Valuation", date: Date.new(2026, 3, 3), amount: 500, currency: "USD",
      entryable: Transaction.new(kind: "investment_value_adjustment"))

    invoke("get_spending_trend", start_date: "2026-03-01", end_date: "2026-03-05")
    assert_response :success, response.body
    body = response.parsed_body
    assert_equal({ "start_date" => "2026-02-01", "end_date" => "2026-02-28" }, body.fetch("previous_period"))
    assert_equal %w[0.0 25.0 25.0 25.0 25.0], body.fetch("current").map { |point| point.fetch("amount") }
    assert_equal 28, body.fetch("previous").length
    assert_equal "100.0", body.fetch("previous").last.fetch("amount")
    assert_equal "25.0", body.fetch("current_total")
    assert_equal "40.0", body.fetch("comparison_total")
    assert_equal "2026-02-05", body.fetch("comparison_end_date")
    assert_equal "-15.0", body.fetch("delta")

    invoke("get_spending_trend", start_date: "2026-01-01", end_date: "2026-04-30")
    assert_response :unprocessable_entity
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

  test "monthly summary returns multi-month series, averages, and category tracking" do
    user = users(:empty)
    @key.update!(user: user)
    account = user.family.accounts.create!(name: "Checking", balance: 0, currency: "USD", accountable: Depository.new)
    groceries = user.family.categories.create!(name: "Groceries")

    travel_to Date.new(2026, 3, 15) do
      account.entries.create!(name: "Jan salary", date: Date.new(2026, 1, 5), amount: -1000, currency: "USD", entryable: Transaction.new)
      account.entries.create!(name: "Jan food", date: Date.new(2026, 1, 10), amount: 200, currency: "USD", entryable: Transaction.new(category: groceries))
      account.entries.create!(name: "Feb salary", date: Date.new(2026, 2, 5), amount: -1200, currency: "USD", entryable: Transaction.new)
      account.entries.create!(name: "Feb food", date: Date.new(2026, 2, 10), amount: 400, currency: "USD", entryable: Transaction.new(category: groceries))
      account.entries.create!(name: "Mar food", date: Date.new(2026, 3, 10), amount: 150, currency: "USD", entryable: Transaction.new(category: groceries))

      invoke("get_monthly_summary", months: 3, include_categories: true, category_id: groceries.id)
      assert_response :success, response.body
      body = response.parsed_body
      assert_equal %w[2026-01-01 2026-02-01 2026-03-01], body.fetch("months").map { |row| row.fetch("month") }
      assert_equal [ false, false, true ], body.fetch("months").map { |row| row.fetch("partial") }
      assert_equal %w[200.0 400.0 150.0], body.fetch("months").map { |row| row.fetch("category_expense") }
      assert_equal "Groceries", body.dig("category", "name")
      assert_equal 2, body.dig("averages", "months_counted")
      assert_equal true, body.dig("averages", "excludes_partial_current_month")
      assert_equal "1100.0", body.dig("averages", "income")
      assert_equal "300.0", body.dig("averages", "expenses")

      invoke("get_monthly_summary", end_month: "2026-03-10")
      assert_response :unprocessable_entity
      invoke("get_monthly_summary", end_month: "2026-04-01")
      assert_response :unprocessable_entity
    end
  end

  test "merchant and tag reports aggregate in family currency and respect permissions and FX" do
    user = users(:empty)
    @key.update!(user: user)
    account = user.family.accounts.create!(name: "Card", balance: 0, currency: "USD", accountable: Depository.new)
    alpha = user.family.merchants.create!(name: "Alpha Market")
    beta = user.family.merchants.create!(name: "Beta Cafe")
    travel_tag = user.family.tags.create!(name: "Trip", user: user)
    other_user = user.family.users.create!(email: "other@example.com", password: "Password123!", role: "member", first_name: "Other", last_name: "User")
    private_tag = user.family.tags.create!(name: "Private", user: other_user)

    tx1 = Transaction.new(merchant: alpha)
    tx1.tags << travel_tag
    tx1.tags << private_tag
    account.entries.create!(name: "Purchase 1", date: Date.new(2026, 3, 5), amount: 80, currency: "USD", entryable: tx1)
    account.entries.create!(name: "Purchase 2", date: Date.new(2026, 3, 6), amount: 40, currency: "USD", entryable: Transaction.new(merchant: alpha))
    account.entries.create!(name: "Coffee", date: Date.new(2026, 3, 7), amount: 30, currency: "USD", entryable: Transaction.new(merchant: beta))
    account.entries.create!(name: "Salary", date: Date.new(2026, 3, 8), amount: -500, currency: "USD", entryable: Transaction.new(merchant: beta))

    invoke("get_merchant_report", start_date: "2026-03-01", end_date: "2026-03-31", type: "expense", limit: 1)
    assert_response :success, response.body
    body = response.parsed_body
    assert_equal "150.0", body.fetch("total_expenses")
    assert_equal true, body.fetch("expenses_truncated")
    assert_equal 1, body.fetch("expenses").length
    assert_equal "Alpha Market", body.fetch("expenses").first.fetch("name")
    assert_equal "120.0", body.fetch("expenses").first.fetch("amount")
    assert_equal 2, body.fetch("expenses").first.fetch("transactions_count")
    assert_equal "60.0", body.fetch("expenses").first.fetch("average")
    assert_equal 80.0, body.fetch("expenses").first.fetch("weight")
    assert_empty body.fetch("income")

    invoke("get_tag_report", start_date: "2026-03-01", end_date: "2026-03-31")
    assert_response :success, response.body
    tag_body = response.parsed_body
    assert_equal [ "Trip" ], tag_body.fetch("expenses").map { |row| row.fetch("name") }
    assert_equal "80.0", tag_body.fetch("expenses").first.fetch("amount")
    assert tag_body.fetch("note").present?

    ExchangeRate.delete_all
    account.entries.create!(name: "FX missing", date: Date.new(2026, 3, 9), amount: 15, currency: "EUR", entryable: Transaction.new(merchant: alpha))
    invoke("get_merchant_report", start_date: "2026-03-01", end_date: "2026-03-31")
    assert_response :unprocessable_entity
    assert_equal "missing_conversion", response.parsed_body.fetch("code")
  end

  test "financial overview returns unified snapshot and search_transactions includes readable names" do
    account = accounts(:depository)
    category = @user.family.categories.create!(name: "Dining")
    merchant = @user.family.merchants.create!(name: "Bistro")
    tag = @user.family.tags.create!(name: "Weekend", user: @user)
    tx = Transaction.new(category: category, merchant: merchant)
    tx.tags << tag
    account.entries.create!(name: "Dinner out", date: Date.current, amount: 45, currency: "USD", entryable: tx)

    invoke("get_financial_overview", months: 2)
    assert_response :success, response.body
    overview = response.parsed_body
    %w[as_of currency net_worth accounts current_month recent_months top_expense_categories shared_expenses budgets goals agenda recent_insights freshness].each do |key|
      assert overview.key?(key), "missing key #{key}"
    end
    assert_equal 2, overview.fetch("recent_months").length

    invoke("search_transactions", search: "Dinner out")
    assert_response :success, response.body
    row = response.parsed_body.fetch("data").first
    assert_equal account.name, row.fetch("account_name")
    assert_equal "Dining", row.dig("transaction", "category_name")
    assert_equal "Bistro", row.dig("transaction", "merchant_name")
    assert_equal [ "Weekend" ], row.dig("transaction", "tag_names")
  end

  private
    def invoke(name, args)
      post "/api/v1/actions/#{name}", params: { arguments: args }, headers: { "X-Api-Key" => @key.display_key }, as: :json
    end
end
