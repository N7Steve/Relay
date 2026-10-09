require "test_helper"

class FinancialConversionPolicyTest < ActiveSupport::TestCase
  include EntriesTestHelper, BalanceTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "FX scope", currency: "USD", balance: 0, accountable: Investment.new(subtype: "brokerage"))
    @date = Date.new(2026, 8, 10)
    @security = securities(:aapl)
    ExchangeRate.where(from_currency: "EUR", to_currency: "USD").delete_all
  end

  test "search totals reject missing conversion and recover when the exact rate is added" do
    create_transaction(account: @account, date: @date, amount: 100, currency: "EUR")
    assert_raises(Money::ConversionError) { Transaction::Search.new(@family).totals }
    ExchangeRate.create!(from_currency: "EUR", to_currency: "USD", date: @date, rate: 1.2)
    assert_equal 120, Transaction::Search.new(@family).totals.expense_money.amount
  end

  test "investment totals and average cost reject missing conversion" do
    create_trade(@security, account: @account, qty: 2, price: 100, currency: "EUR", date: @date)
    query = InvestmentStatement::Totals.new(@family, account_ids: [ @account.id ], date_range: @date..@date)
    assert_raises(Money::ConversionError) { query.call }
    holding = Holding.new(account: @account, security: @security, date: @date, currency: "USD", qty: 2, price: 120, amount: 240)
    assert_raises(Money::ConversionError) { holding.avg_cost }
    ExchangeRate.create!(from_currency: "EUR", to_currency: "USD", date: @date, rate: 1.2)
    assert_equal 240, query.call.fetch(:contributions)
    assert_equal 120, holding.avg_cost.amount
  end

  test "balance series cannot return partial foreign totals and same currency remains exact" do
    @account.update!(currency: "EUR")
    create_balance(account: @account, date: @date, balance: 100)
    period = Period.custom(start_date: @date, end_date: @date)
    builder = Balance::ChartSeriesBuilder.new(account_ids: [ @account.id ], currency: "USD", period: period)
    assert_raises(Money::ConversionError) { builder.balance_series }
    same = Balance::ChartSeriesBuilder.new(account_ids: [ @account.id ], currency: "EUR", period: period)
    assert_equal 100, same.balance_series.last.value.amount
  end
end
