require "test_helper"

class RetiredFinancekitIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @account = accounts(:depository)
    @account.update!(reverse_balance_history: true)
    @publisher_id = SecureRandom.uuid
  end

  test "former publisher and connection endpoints are not routed" do
    api_key = ApiKey.create!(user: @user, name: "Retired FinanceKit", scopes: [ "read_write" ],
      display_key: "test_rw_#{SecureRandom.hex(8)}", source: "web")
    headers = { "X-Api-Key" => api_key.display_key, "Authorization" => "Bearer #{SecureRandom.hex(32)}" }

    get "/api/v1/financekit/capabilities", headers: headers
    assert_response :not_found
    post "/api/v1/financekit/connections", headers: headers
    assert_response :not_found
    post "/api/v1/financekit/publishers/#{@publisher_id}/batches", headers: headers, params: "{}"
    assert_response :not_found
    get "/api/v1/financekit/publishers/#{@publisher_id}/batches/#{SecureRandom.uuid}", headers: headers
    assert_response :not_found
  end

  test "historically linked accounts appear in the ordinary account groups" do
    sign_in @user

    get accounts_path

    assert_response :success
    assert_select "#financekit-accounts", count: 0
    assert_select "#manual-accounts a[href=?]", account_path(@account)
  end
end
