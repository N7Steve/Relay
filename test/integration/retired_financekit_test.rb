require "test_helper"
require_relative "../support/historical_financekit_helper"

class RetiredFinancekitIntegrationTest < ActionDispatch::IntegrationTest
  include HistoricalFinancekitHelper

  setup do
    @user = users(:family_admin)
    @account = accounts(:depository)
    @item, @lineage = create_historical_financekit_link(account: @account)
  end

  test "former publisher and connection endpoints are not routed" do
    api_key = ApiKey.create!(user: @user, name: "Retired FinanceKit", scopes: [ "read_write" ],
      display_key: "test_rw_#{SecureRandom.hex(8)}", source: "web")
    headers = { "X-Api-Key" => api_key.display_key, "Authorization" => "Bearer #{SecureRandom.hex(32)}" }

    get "/api/v1/financekit/capabilities", headers: headers
    assert_response :not_found
    post "/api/v1/financekit/connections", headers: headers
    assert_response :not_found
    post "/api/v1/financekit/publishers/#{@item.publisher_id}/batches", headers: headers, params: "{}"
    assert_response :not_found
    get "/api/v1/financekit/publishers/#{@item.publisher_id}/batches/#{SecureRandom.uuid}", headers: headers
    assert_response :not_found
  end

  test "historically linked accounts appear in the ordinary account groups" do
    sign_in @user

    get accounts_path

    assert_response :success
    assert_select "#financekit-accounts", count: 0
    assert_select "#manual-accounts a[href=?]", account_path(@account)
  end

  test "unlinking a historical Wallet account keeps its data and the historical connection" do
    sign_in @user

    get confirm_unlink_account_path(@account)
    assert_response :success
    assert_no_match "Apple Wallet connection", response.body

    assert_no_difference [ "Entry.count", "FinancekitItem.count", "FinancekitAccountLineage.count" ] do
      delete unlink_account_path(@account)
    end

    assert_redirected_to accounts_path
    assert_empty @account.reload.account_providers
    assert_equal "active", @item.reload.status
  end
end
