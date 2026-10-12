require "test_helper"

class Reports::ActivityTest < ActiveSupport::TestCase
  setup do
    @user = users(:empty)
    @family = @user.family
    @cash = @family.accounts.create!(name: "Cash", balance: 0, currency: "USD", accountable: Depository.new)
    @portfolio = @family.accounts.create!(name: "Managed", balance: 1000, currency: "USD",
      accountable: Investment.new(subtype: "roboadvisor"))
    @period = Period.custom(start_date: Date.new(2026, 8, 1), end_date: Date.new(2026, 8, 31))
  end

  test "adds native gains once to income while capital transfers remain excluded" do
    movement(@cash, -1000)
    movement(@cash, 200)
    movement(@portfolio, -300, kind: "investment_contribution")
    movement(@portfolio, 100, kind: "funds_movement")
    movement(@portfolio, -50, kind: "investment_value_adjustment")
    movement(@portfolio, -10, investment_activity_label: "Dividend")
    movement(@portfolio, 4, investment_activity_label: "Fee")

    report = Reports::Activity.new(@family, user: @user)
    totals = report.totals(period: @period)
    assert_equal 56, totals.investment_return.amount
    assert_equal 1056, totals.income.amount
    assert_equal 200, totals.expenses.amount
    assert_equal 1056, report.totals(period: @period).income.amount
    # Budgets retain their existing cash-only definition.
    assert_equal 1010, IncomeStatement.new(@family, user: @user).income_totals(period: @period).total
  end

  test "losses reduce income and native returns do not change adjusted spending" do
    movement(@cash, -1000)
    shared = movement(@cash, 200)
    shared.transaction.update!(shared_expense: true)
    movement(@portfolio, 50, kind: "investment_value_adjustment")
    report = Reports::Activity.new(@family, user: @user)

    assert_equal(-50, report.totals(period: @period).investment_return.amount)
    assert_equal 950, report.totals(period: @period).income.amount
    calculator = SharedExpensesCalculator.new(@family, transactions: report.cash_transactions)
    assert_equal 100, calculator.calculate_adjusted_expenses(@period).amount
  end

  test "uses the canonical balance-derived return and keeps periods separate" do
    @portfolio.balances.create!(date: @period.start_date - 1, balance: 1000, currency: "USD", cash_adjustments: 1000)
    @portfolio.balances.create!(date: @period.start_date, balance: 1075, currency: "USD", cash_adjustments: 75)
    movement(@portfolio, -500, kind: "investment_contribution")
    movement(@portfolio, -20, kind: "investment_value_adjustment", date: @period.end_date + 1)
    report = Reports::Activity.new(@family, user: @user)
    assert_equal 75, report.investment_return(period: @period).amount
    assert_equal 75, report.totals(period: @period).income.amount
  end

  test "includes provider native monetary performance without counting contributed capital" do
    @portfolio.update!(imported_performance: {
      return: { index: { "2026-07-31" => "100", "2026-08-01" => "110", "2026-08-02" => "121" } },
      portfolios: [ { date: "2026-07-31", total_amount: "1000" }, { date: "2026-08-01", total_amount: "1600" } ]
    })
    movement(@portfolio, -500, kind: "investment_contribution")
    report = Reports::Activity.new(@family, user: @user)

    assert_equal 260, report.investment_return(period: @period).amount
    assert_equal 260, report.totals(period: @period).income.amount
  end

  test "respects family finance access exclusions pending status and account filters" do
    movement(@portfolio, -50, kind: "investment_value_adjustment")
    movement(@portfolio, -500, kind: "investment_value_adjustment", excluded: true)
    movement(@portfolio, -500, kind: "investment_value_adjustment", posting_status: "pending")
    partner = @family.accounts.create!(name: "Partner", owner: users(:sure_support_staff), balance: 1000,
      currency: "USD", accountable: Investment.new(subtype: "roboadvisor"))
    partner.account_shares.create!(user: @user, permission: "read_only", include_in_finances: false)
    movement(partner, -500, kind: "investment_value_adjustment")
    other = families(:dylan_family).accounts.create!(name: "Other family", balance: 1000,
      currency: "USD", accountable: Investment.new(subtype: "roboadvisor"))
    movement(other, -500, kind: "investment_value_adjustment")

    report = Reports::Activity.new(@family, user: @user)
    assert_equal 50, report.investment_return(period: @period).amount
    assert_equal 0, report.investment_return(period: @period, account_id: partner.id).amount
    assert_equal 50, report.investment_return(period: @period, account_id: @portfolio.id).amount

    @portfolio.update!(exclude_from_reports: true)
    assert_equal 0, Reports::Activity.new(@family, user: @user).totals(period: @period).income.amount
  end

  test "foreign portfolio returns use stored conversion and fail if it is missing" do
    @portfolio.update!(currency: "EUR")
    ExchangeRate.find_or_initialize_by(from_currency: "EUR", to_currency: "USD", date: Date.current).update!(rate: 2)
    movement(@portfolio, -50, kind: "investment_value_adjustment", currency: "EUR")
    # The performance engine first converts entry currency to account currency.
    assert_equal 100, Reports::Activity.new(@family, user: @user).investment_return(period: @period).amount
    ExchangeRate.where(from_currency: "EUR", to_currency: "USD").delete_all
    assert_raises(Money::ConversionError) { Reports::Activity.new(@family, user: @user).totals(period: @period) }
  end

  private
    def movement(account, amount, kind: "standard", investment_activity_label: nil, posting_status: nil, **attributes)
      account.entries.create!({ name: "Movement", amount: amount, date: @period.start_date + 10,
        currency: account.currency, entryable: Transaction.new(kind: kind, investment_activity_label: investment_activity_label,
          posting_status: posting_status) }.merge(attributes))
    end
end
