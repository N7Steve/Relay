# frozen_string_literal: true

require "test_helper"

class Api::V1::InvestmentOperationsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @key = ApiKey.create!(user: @user, name: "Investment", scopes: %w[read_write], source: "web", display_key: "investment_#{SecureRandom.hex(12)}")
    @account = accounts(:investment)
  end

  test "native trade creation replay editing unlock and deletion preserve cash signs and fees" do
    args = { account_id: @account.id, type: "buy", date: Date.current.iso8601, ticker: "AAPL", qty: "2", price: "100", fee: "3", idempotency_key: "buy" }
    invoke("create_trade", args)
    assert_response :success, response.body
    id = response.parsed_body.fetch("entryable_id")
    assert_equal 203.to_d, Trade.find(id).entry.amount
    invoke("create_trade", args)
    assert_response :success
    assert_equal 1, @account.trades.where(qty: 2, price: 100).count
    invoke("update_trade", trade_id: id, type: "sell", qty: "1", price: "105", fee: "2", idempotency_key: "sell")
    assert_response :success, response.body
    assert_equal(-103.to_d, Trade.find(id).entry.amount)
    assert_equal(-1.to_d, Trade.find(id).qty)
    invoke("get_trade", trade_id: id)
    assert_response :success
    invoke("list_trades", account_id: @account.id)
    assert_response :success
    invoke("unlock_trade", trade_id: id, idempotency_key: "unlock")
    assert_response :success
    invoke("delete_trade", trade_id: id, idempotency_key: "delete")
    assert_response :success
    assert_not Trade.exists?(id)
  end

  test "income and investment transfer use native entry types and counterparty permissions" do
    invoke("create_trade", account_id: @account.id, type: "interest", date: Date.current.iso8601, amount: "5", idempotency_key: "interest")
    assert_response :success, response.body
    assert_equal "-5.0", response.parsed_body.fetch("amount")
    invoke("create_trade", account_id: @account.id, type: "deposit", date: Date.current.iso8601, amount: "20", transfer_account_id: accounts(:depository).id, idempotency_key: "deposit")
    assert_response :success, response.body
    assert_equal "confirmed", response.parsed_body.fetch("status")
    assert_equal "investment_contribution", response.parsed_body.dig("outflow", "transaction", "kind")
    invoke("create_trade", account_id: @account.id, type: "buy", date: Date.current.iso8601, ticker: "AAPL", qty: "0", price: "10", idempotency_key: "zero")
    assert_response :unprocessable_entity
  end

  test "cost basis uses total to per share conversion and remains locked until explicit unlock" do
    row = holdings(:one)
    invoke("update_holding_cost_basis", holding_id: row.id, total_cost_basis: "500", idempotency_key: "basis")
    assert_response :success, response.body
    assert_equal 50.to_d, row.reload.cost_basis
    assert row.cost_basis_locked?
    invoke("unlock_holding_cost_basis", holding_id: row.id, idempotency_key: "unlock-basis")
    assert_response :success
    assert_not row.reload.cost_basis_locked?
    invoke("get_holding", holding_id: row.id)
    assert_response :success
    invoke("list_holdings", account_id: @account.id)
    assert_response :success
  end

  test "reconciliation preview does not save and actual reconciliation replays without another valuation" do
    args = { account_id: accounts(:depository).id, amount: "8000", date: Date.current.iso8601 }
    assert_no_difference "Valuation.count" do
      invoke("preview_reconciliation", args)
      assert_response :success, response.body
    end
    assert_difference "Valuation.count", 1 do
      invoke("reconcile_account", args.merge(idempotency_key: "reconcile"))
      assert_response :success, response.body
      invoke("reconcile_account", args.merge(idempotency_key: "reconcile"))
      assert_response :success
    end
    row = accounts(:depository).entries.valuations.find_by!(date: Date.current)
    invoke("update_valuation", valuation_id: row.entryable_id, amount: "8100", date: Date.current.iso8601, idempotency_key: "edit-valuation")
    assert_response :success, response.body
    assert_equal 8100.to_d, row.reload.amount
    invoke("delete_valuation", valuation_id: row.entryable_id, idempotency_key: "delete-valuation")
    assert_response :success
  end

  test "shared market writes require instance authority while saved prices are account scoped" do
    invoke("set_exchange_rate", from_currency: "EUR", to_currency: "USD", date: Date.current.iso8601, rate: "1.1", idempotency_key: "fx-denied")
    assert_response :forbidden
    @user.update!(role: "super_admin")
    invoke("set_exchange_rate", from_currency: "EUR", to_currency: "USD", date: Date.current.iso8601, rate: "1.1", idempotency_key: "fx")
    assert_response :success, response.body
    invoke("set_exchange_rate", from_currency: "EUR", to_currency: "USD", date: Date.current.iso8601, rate: "0", idempotency_key: "fx-zero")
    assert_response :unprocessable_entity
    invoke("set_local_price", security_id: securities(:aapl).id, date: Date.current.iso8601, price: "215", currency: "USD", idempotency_key: "price")
    assert_response :success, response.body
    invoke("list_local_prices", security_id: securities(:aapl).id)
    assert_response :success
  end

  test "private investment accounts are outside another family member scope" do
    @user = users(:family_member)
    @account.account_shares.where(user: @user).destroy_all
    @key.update!(user: @user)
    invoke("get_trade", trade_id: trades(:one).id)
    assert_response :not_found
    invoke("get_holding", holding_id: holdings(:one).id)
    assert_response :not_found
    invoke("list_local_prices", security_id: securities(:aapl).id)
    assert_response :not_found
  end

  test "managed portfolio absolute value excludes contributions from its return" do
    row = @user.family.accounts.create!(name: "Managed API", balance: 1000, currency: "USD", owner: @user, accountable: Investment.new(subtype: "roboadvisor"))
    opening = Date.current - 30
    row.entries.create!(date: opening, amount: 1000, currency: "USD", name: "Opening", entryable: Valuation.new(kind: "opening_anchor"))
    row.entries.create!(date: opening + 1, amount: -300, currency: "USD", name: "Contribution", entryable: Transaction.new(kind: "investment_contribution"))
    invoke("update_managed_portfolio_value", account_id: row.id, date: (opening + 1).iso8601, amount: "1400", idempotency_key: "managed")
    assert_response :success, response.body
    assert_equal(-100.to_d, row.transactions.find_by!(kind: "investment_value_adjustment").entry.amount)
    assert_equal 100.to_d, Investment::RoboadvisorPerformance.new(row.reload).total_profit_loss
  end

  test "remap collision merges positions and reset preserves native provider link" do
    row = holdings(:one)
    target = Security::Resolver.new("LOCALTEST").resolve
    @account.holdings.create!(security: target, date: row.date, currency: row.currency, qty: 2, price: 215, amount: 430)
    invoke("remap_holding_security", holding_id: row.id, ticker: "LOCALTEST", idempotency_key: "remap")
    assert_response :success, response.body
    id = response.parsed_body.fetch("id")
    # The native materializer rebuilds calculated holdings from the remapped trades.
    assert_equal 10.to_d, Holding.find(id).qty
    assert_equal target, trades(:one).reload.security
    invoke("reset_holding_security", holding_id: id, idempotency_key: "reset-security")
    assert_response :success, response.body
    assert_equal securities(:aapl), trades(:one).reload.security
  end

  test "holding deletion previews all affected trades and rejects a changed plan" do
    row = holdings(:one)
    trade_id = trades(:one).id
    invoke("preview_holding_deletion", holding_id: row.id)
    assert_response :success, response.body
    token = response.parsed_body.fetch("preview_token")
    entries(:trade).update!(notes: "changed")
    invoke("delete_holding", holding_id: row.id, preview_token: token, idempotency_key: "stale-delete")
    assert_response :unprocessable_entity
    invoke("preview_holding_deletion", holding_id: row.id)
    token = response.parsed_body.fetch("preview_token")
    invoke("delete_holding", holding_id: row.id, preview_token: token, idempotency_key: "holding-delete")
    assert_response :success, response.body
    assert_not Trade.exists?(trade_id)
  end

  test "missing remap prices return an explicit financial error and roll back the remap" do
    row = holdings(:one)
    original = row.security_id
    materializer = mock
    Balance::Materializer.expects(:new).returns(materializer)
    materializer.expects(:materialize_balances).raises(Security::MissingPriceError, "No local price")
    invoke("remap_holding_security", holding_id: row.id, ticker: "MISSINGLOCAL", idempotency_key: "missing-price")
    assert_response :unprocessable_entity
    assert_match(/No local price/, response.body)
    assert_equal original, row.reload.security_id
  end

  private
    def invoke(name, args)
      post "/api/v1/actions/#{name}", params: { arguments: args }, headers: { "X-Api-Key" => @key.display_key }, as: :json
    end
end
