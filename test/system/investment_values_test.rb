require "application_system_test_case"

class InvestmentValuesTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
    @account = @user.family.accounts.create!(name: "Native portfolio", owner: @user,
      balance: 1000, currency: "USD", accountable: Investment.new(subtype: "roboadvisor"))
    @account.entries.create!(date: Date.current - 2, amount: 1000, currency: "USD", name: "Opening",
      entryable: Valuation.new(kind: "opening_anchor"))
  end

  test "updates the total and corrects the recorded value through the native drawer" do
    visit account_path(@account)
    click_link "Update value", match: :first
    within "turbo-frame#modal" do
      assert_text "Update portfolio value"
      fill_in "Total portfolio value", with: "1114.71"
      click_button "Update value"
    end
    assert_text "Portfolio value updated"
    assert_text "+$114.71"
    entry = @account.entries.transactions.order(:created_at).last
    click_link entry.name
    within "turbo-frame#drawer" do
      fill_in "Total portfolio value", with: "950"
      click_button "Update value"
    end
    assert_text "Portfolio value updated"
    assert_text "-$50.00"
    assert_equal 950, @account.reload.balance
    assert_equal 1, @account.transactions.where(kind: "investment_value_adjustment").count
  end
end
