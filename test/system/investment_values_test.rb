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
    within "turbo-frame#entry_#{entry.id}" do
      assert_selector "input[type='checkbox'][disabled]"
      assert_selector ".text-success[role='img'][aria-label='Portfolio value increased'] svg"
    end
    click_link entry.name
    within "turbo-frame#drawer" do
      fill_in "Total portfolio value", with: "950"
      click_button "Update value"
    end
    assert_text "Portfolio value updated"
    assert_text "-$50.00"
    within "turbo-frame#entry_#{entry.id}" do
      assert_selector "input[type='checkbox'][disabled]"
      assert_selector ".text-destructive[role='img'][aria-label='Portfolio value decreased'] svg"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/native-valuation-direction.png"))
    assert_equal 950, @account.reload.balance
    assert_equal 1, @account.transactions.where(kind: "investment_value_adjustment").count
  end

  test "switches between return and balance while keeping the selected period" do
    assert Investment::ValueUpdate.new(account: @account, date: Date.current, amount: 1050).save

    visit account_path(@account, period: "last_7_days")
    within "##{dom_id(@account, :chart)}" do
      assert_text "Cumulative return for the period"
      assert_text "+$50.00"
      assert_selector "#lineChart svg path[d]"
      page.save_screenshot(Rails.root.join("tmp/screenshots/managed-portfolio-return.png"))
      click_link "Balance", exact: true
    end
    assert_current_path account_path(@account, chart_view: "balance", period: "last_7_days")
    within "##{dom_id(@account, :chart)}" do
      assert_text "$1,050.00"
      click_link "Return", exact: true
    end
    assert_current_path account_path(@account, chart_view: "performance", period: "last_7_days")
    within "##{dom_id(@account, :chart)}" do
      assert_text "+$50.00"
      assert_selector "[data-time-series-chart-show-change-value='false'] svg path[d]"
    end
  end
end
