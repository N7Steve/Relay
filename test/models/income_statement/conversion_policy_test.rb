require "test_helper"

class IncomeStatement::ConversionPolicyTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @family.update!(currency: "USD")
    @account = @family.accounts.create!(name: "Reports", accountable: Depository.new, currency: "USD", balance: 0)
    @date = Date.new(2026, 8, 10)
    @scope = @account.transactions
  end

  test "all four aggregate queries fail explicitly on a missing foreign rate" do
    create_transaction(account: @account, date: @date, amount: 100, currency: "EUR")

    queries.each do |query|
      error = assert_raises(Money::ConversionError) { query.call }
      assert_equal "EUR", error.from_currency
      assert_equal "USD", error.to_currency
      assert_equal @date, error.date
    end
  end

  test "same currency uses unity even if an unrelated identity rate exists" do
    create_transaction(account: @account, date: @date, amount: 100)
    ExchangeRate.create!(from_currency: "USD", to_currency: "USD", date: @date, rate: 2)

    assert_equal 100, totals_query.call.sum(&:total)
    assert_equal 100, daily_query.call.sum(&:total)
  end

  test "stored foreign rate converts totals and statistics exactly" do
    create_transaction(account: @account, date: @date, amount: 100, currency: "EUR")
    ExchangeRate.create!(from_currency: "EUR", to_currency: "USD", date: @date, rate: 1.2)

    assert_equal 120, totals_query.call.sum(&:total)
    assert_equal 120, daily_query.call.sum(&:total)
    assert_equal 120, family_stats_query.call.first.avg
    assert_equal 120, category_stats_query.call.first.avg
  end

  test "missing rates on excluded exceptional and investment contribution rows cannot block a report" do
    create_transaction(account: @account, date: @date, amount: 100)
    create_transaction(account: @account, date: @date, amount: 5_000, currency: "EUR", excluded: true)
    create_transaction(account: @account, date: @date, amount: 5_000, currency: "EUR", entryable: Transaction.new(forecast_behavior: "exceptional_once"))
    create_transaction(account: @account, date: @date, amount: 5_000, currency: "EUR", kind: "investment_contribution")

    assert_equal 100, totals_query.call.sum(&:total)
    assert_equal 100, daily_query.call.sum(&:total)
    assert_equal 100, family_stats_query.call.first.avg
    assert_equal 100, category_stats_query.call.first.avg
  end

  test "foreign movements outside the selected accounts do not block a user's aggregates" do
    create_transaction(account: @account, date: @date, amount: 100)
    other = @family.accounts.create!(name: "Unselected", accountable: Depository.new, currency: "EUR", balance: 0)
    create_transaction(account: other, date: @date, amount: 1_000, currency: "EUR")
    scope = @family.transactions
    totals = IncomeStatement::Totals.new(@family, transactions_scope: scope, date_range: @date..@date, included_account_ids: [ @account.id ])
    daily = IncomeStatement::DailyExpenseTotals.new(@family, transactions_scope: scope, date_range: @date..@date, included_account_ids: [ @account.id ])

    assert_equal 100, totals.call.sum(&:total)
    assert_equal 100, daily.call.sum(&:total)
    assert_equal 100, family_stats_query.call.first.avg
    assert_equal 100, category_stats_query.call.first.avg
  end

  test "both totals query shapes reject a partial result even when other rows have known rates" do
    create_transaction(account: @account, date: @date, amount: 100)
    create_transaction(account: @account, date: @date, amount: 100, currency: "EUR")

    [ true, false ].each do |include_trades|
      query = IncomeStatement::Totals.new(@family, transactions_scope: @scope, date_range: @date..@date, include_trades: include_trades)
      assert_raises(Money::ConversionError) { query.call }
    end
  end

  private

    def totals_query
      IncomeStatement::Totals.new(@family, transactions_scope: @scope, date_range: @date..@date)
    end

    def daily_query
      IncomeStatement::DailyExpenseTotals.new(@family, transactions_scope: @scope, date_range: @date..@date)
    end

    def family_stats_query
      IncomeStatement::FamilyStats.new(@family, account_ids: [ @account.id ])
    end

    def category_stats_query
      IncomeStatement::CategoryStats.new(@family, account_ids: [ @account.id ])
    end

    def queries
      [ totals_query, daily_query, family_stats_query, category_stats_query ]
    end
end
