require "test_helper"

class ManagedTransfersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @bank = @user.family.accounts.create!(name: "Bank", owner: @user, balance: 1000, currency: "USD", accountable: Depository.new)
    @portfolio = @user.family.accounts.create!(name: "Portfolio", owner: @user, balance: 0, currency: "USD", accountable: Investment.new(subtype: "roboadvisor"))
  end

  test "creation and tampered updates retain the canonical name and classification" do
    post transfers_path, params: { transfer: { from_account_id: @bank.id, to_account_id: @portfolio.id,
      amount: 100, date: Date.current, name: "Groceries", category_id: categories(:food_and_drink).id } }
    assert_response :redirect
    transfer = Transfer.order(:created_at).last
    assert_equal "Contribution · Portfolio", transfer.name
    get transfer_path(transfer)
    assert_response :success
    assert_select "input[name='transfer[name]']", count: 0
    assert_select "input[name='transfer[category_id]']", count: 0
    assert_select "input[name='transfer[amount]']"
    patch transfer_path(transfer), params: { transfer: { name: "Shopping", category_id: categories(:food_and_drink).id, notes: "Keep notes" } }
    assert_response :redirect
    assert_equal "Keep notes", transfer.reload.notes
    [ transfer.outflow_transaction, transfer.inflow_transaction ].each do |transaction|
      assert_nil transaction.category_id
      assert_equal "Contribution · Portfolio", transaction.entry.name
    end
  end

  test "contribution form preselects the destination portfolio" do
    get new_transfer_path(to_account_id: @portfolio.id)
    assert_response :success
    assert_select "input[name='transfer[to_account_id]'][value=?]", @portfolio.id
    assert_select "[data-managed-transfer-accounts-value]"
  end
end
