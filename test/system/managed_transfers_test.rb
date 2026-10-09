require "application_system_test_case"

class ManagedTransfersTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
    @portfolio = @user.family.accounts.create!(name: "Managed portfolio", owner: @user, balance: 0,
      currency: "USD", accountable: Investment.new(subtype: "roboadvisor"))
  end

  test "account selection controls the native fields and the saved transfer drawer" do
    visit new_transfer_path(to_account_id: @portfolio.id)
    select_ds("From", accounts(:depository))
    assert_text "Contribution · Managed portfolio"
    assert_selector "fieldset[data-managed-transfer-target='editableFields'][disabled]", visible: :all
    assert_no_selector "input[name='transfer[name]']", visible: true
    select_ds("To", accounts(:credit_card))
    assert_selector "input[name='transfer[name]']", visible: true
    select_ds("To", @portfolio)
    fill_in "transfer[amount]", with: 100
    click_button "Create transfer"
    assert_text "Transfer created"
    transfer = Transfer.order(:created_at).last
    visit transfer_path(transfer)
    assert_text "Contribution · Managed portfolio"
    find("summary", text: /details/i).click
    assert_no_selector "input[name='transfer[name]']", visible: :all
    assert_no_selector "input[name='transfer[category_id]']", visible: :all
    assert_selector "input[name='transfer[amount]']"
    page.save_screenshot(Rails.root.join("tmp/screenshots/native-managed-transfer.png"))
  end
end
