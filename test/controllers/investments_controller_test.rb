require "test_helper"

class InvestmentsControllerTest < ActionDispatch::IntegrationTest
  include AccountableResourceInterfaceTest

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:investment)
  end

  test "editing preserves legacy catalogue choice and saves independent tax and tracking settings" do
    @account.accountable.update!(subtype: "401k")
    trade_ids = @account.trades.pluck(:id)

    get edit_investment_path(@account)
    assert_response :success
    assert_select "select[name='account[subtype]'] option[value='401k']", 1
    assert_select "select[name='account[accountable_attributes][tax_treatment]']", 1
    assert_select "select[name='account[accountable_attributes][tracking_mode]']", 1

    patch investment_path(@account), params: { account: { subtype: "roboadvisor", accountable_attributes: { id: @account.accountable_id, tax_treatment: "tax_exempt", tracking_mode: "positions" } } }

    assert_response :redirect
    assert_equal :tax_exempt, @account.reload.tax_treatment
    assert_not @account.managed_portfolio?
    assert_equal trade_ids.sort, @account.trades.pluck(:id).sort
  end

  test "new investment form only offers the short catalogue" do
    get new_investment_path
    assert_response :success
    options = css_select("select[name='account[subtype]'] option").map { |option| option["value"] }.reject(&:blank?)
    assert_equal %w[brokerage roboadvisor pension other], options
    assert_select "select[name='account[subtype]'] option[value='401k']", 0
  end
end
