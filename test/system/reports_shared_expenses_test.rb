require "application_system_test_case"

class ReportsSharedExpensesTest < ApplicationSystemTestCase
  test "shared expense toggle updates the breakdown and survives period navigation" do
    user = users(:family_admin)
    category = user.family.categories.create!(name: "Shared supermarket")
    accounts(:depository).entries.create!(name: "Groceries", amount: 200, currency: "USD", date: Date.current,
      entryable: Transaction.new(category: category, shared_expense: true))
    sign_in user
    visit reports_path(period_type: :monthly)

    row = "tr[data-category='category-#{category.id}']"
    assert_selector "#{row} .privacy-sensitive", text: "$200.00"
    find("label[for='adjust_shared_expenses']", text: I18n.t("reports.transactions_breakdown.adjust_shared_expenses")).click
    assert_selector "#{row} .privacy-sensitive", text: "$100.00"
    assert_selector "input#adjust_shared_expenses[checked]", visible: :all

    click_link I18n.t("reports.index.periods.ytd")
    assert_current_path reports_path(period_type: :ytd, adjust_shared_expenses: "1")
    assert_selector "#{row} .privacy-sensitive", text: "$100.00"
    find("label[for='adjust_shared_expenses']", text: I18n.t("reports.transactions_breakdown.adjust_shared_expenses")).click
    assert_selector "#{row} .privacy-sensitive", text: "$200.00"
  end
end
