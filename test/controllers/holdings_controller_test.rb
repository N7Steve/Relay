require "test_helper"

class HoldingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @account = accounts(:investment)
    @holding = @account.holdings.first
  end

  test "gets holdings" do
    get holdings_url(account_id: @account.id)
    assert_response :success
  end

  test "gets holding" do
    get holding_path(@holding)

    assert_response :success
  end

  test "shows exact share count without rounding" do
    @holding.update!(qty: 10.374)

    get holding_path(@holding)

    assert_select "##{dom_id(@holding, :shares)}", text: "10.374"
  end

  test "shows the exact stored quantity for a small crypto holding in the holdings list" do
    account = accounts(:crypto)
    security = Security.create!(
      ticker: "CRYPTO:BTC",
      name: "Bitcoin",
      exchange_operating_mic: "XCBS",
      offline: true
    )
    holding = account.holdings.create!(
      security: security,
      date: Date.current,
      qty: BigDecimal("0.000000000000000148"),
      price: 100_000,
      amount: 14.884,
      currency: "USD"
    )

    get holdings_url(account_id: account.id)

    assert_select "##{dom_id(holding)} p", text: "0.000000000000000148 shares"
  end

  test "destroys holding and associated entries" do
    assert_difference -> { Holding.count } => -1,
                      -> { Entry.count } => -1 do
      delete holding_path(@holding)
    end

    assert_redirected_to account_path(@holding.account)
    assert_empty @holding.account.entries.where(entryable: @holding.account.trades.where(security: @holding.security))
  end

  test "updates cost basis with total amount divided by qty" do
    # Given: holding with 10 shares
    @holding.update!(qty: 10, cost_basis: nil, cost_basis_source: nil, cost_basis_locked: false)

    # When: user submits total cost basis of $100 (should become $10 per share)
    patch holding_path(@holding), params: { holding: { cost_basis: "100.00" } }

    # Redirects to account page holdings tab to refresh list
    assert_redirected_to account_path(@holding.account, tab: "holdings")
    @holding.reload

    # Then: cost_basis should be per-share ($10), not total
    assert_equal 10.0, @holding.cost_basis.to_f
    assert_equal "manual", @holding.cost_basis_source
    assert @holding.cost_basis_locked?
  end

  test "unlock_cost_basis removes lock" do
    # Given: locked holding
    @holding.update!(cost_basis: 50.0, cost_basis_source: "manual", cost_basis_locked: true)

    # When: user unlocks
    post unlock_cost_basis_holding_path(@holding)

    # Redirects to account page holdings tab to refresh list
    assert_redirected_to account_path(@holding.account, tab: "holdings")
    @holding.reload

    # Then: lock is removed but cost_basis and source remain
    assert_not @holding.cost_basis_locked?
    assert_equal 50.0, @holding.cost_basis.to_f
    assert_equal "manual", @holding.cost_basis_source
  end

  test "remap_security accepts a typed ticker and reuses the stored security" do
    msft = securities(:msft)

    patch remap_security_holding_path(@holding), params: { security_id: " MSFT|XNAS " }

    assert_redirected_to account_path(@holding.account, tab: "holdings")
    assert_equal msft.id, @holding.reload.security_id
  end

  test "remap_security creates an offline security for an unknown ticker" do
    assert_difference "Security.count", 1 do
      patch remap_security_holding_path(@holding), params: { security_id: "NEWCO" }
    end

    security = @holding.reload.security
    assert_equal "NEWCO", security.ticker
    assert security.offline?
  end

  test "price sync and provider search are no longer routed" do
    get holding_path(@holding)

    assert_response :success
    assert_no_match "sync_prices", response.body
    assert_select "input[name='security_id'][type='text']"
    assert_not respond_to?(:sync_prices_holding_path)
    assert_not respond_to?(:securities_path)
  end
end
