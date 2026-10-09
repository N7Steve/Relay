require "test_helper"

class InvestmentValuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @account = @user.family.accounts.create!(name: "Managed", balance: 1000, currency: "USD",
      owner: @user, accountable: Investment.new(subtype: "roboadvisor"))
    @account.entries.create!(name: "Opening", date: Date.current - 2, amount: 1000, currency: "USD",
      entryable: Valuation.new(kind: "opening_anchor"))
  end

  test "form creates a native adjustment and renders signed history with its total" do
    get new_investment_value_path(account_id: @account.id)
    assert_response :success
    assert_select "input[name='investment_value[amount]']"
    assert_difference "Entry.count", 1 do
      post investment_values_path, params: { investment_value: { account_id: @account.id, amount: "1114.71", date: Date.current } }
    end
    assert_redirected_to account_path(@account)
    entry = @account.entries.transactions.order(:created_at).last
    assert_equal BigDecimal("-114.71"), entry.amount
    get investment_value_path(entry)
    assert_response :success
    assert_match "114.71", response.body
    get account_path(@account)
    assert_response :success
    assert_select "a[href=?]", new_investment_value_path(account_id: @account.id)
    assert_select "a[href=?]", investment_value_path(entry)
  end

  test "invalid input retains errors and creates no movements" do
    assert_no_difference "Entry.count" do
      post investment_values_path, params: { investment_value: { account_id: @account.id, amount: -1, date: Date.current } }
    end
    assert_response :unprocessable_entity
  end

  test "another family cannot read or write the account" do
    @account.update_column(:family_id, families(:empty).id)
    get new_investment_value_path(account_id: @account.id)
    assert_response :not_found
    assert_no_difference "Entry.count" do
      post investment_values_path, params: { investment_value: { account_id: @account.id, amount: 100, date: Date.current } }
    end
    assert_response :not_found
  end

  test "ordinary accounts cannot use the managed value endpoint" do
    get new_investment_value_path(account_id: accounts(:depository).id)
    assert_response :not_found
  end

  test "read-only sharing allows history but refuses value changes" do
    update = Investment::ValueUpdate.new(account: @account, amount: 1100)
    assert update.save
    @account.share_with!(users(:family_member), permission: "read_only")
    sign_in users(:family_member)
    get investment_value_path(update.entry)
    assert_response :success
    assert_select "form[action=?]", investment_value_path(update.entry), count: 0
    assert_no_difference "Entry.count" do
      post investment_values_path, params: { investment_value: { account_id: @account.id, amount: 1200, date: Date.current } }
    end
    assert_response :redirect
    assert_equal 1100, @account.reload.balance
  end
end
