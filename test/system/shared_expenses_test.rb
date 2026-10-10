require "application_system_test_case"

class SharedExpensesTest < ApplicationSystemTestCase
  setup do
    sign_in users(:family_admin)
  end

  test "create a shared expense and a settlement and clear classification in the drawer" do
    %w[outflow inflow].each do |nature|
      visit new_transaction_url(account_id: accounts(:depository).id, nature: nature)
      fill_in "Description", with: "Shared #{nature}"
      fill_in "entry_amount", with: "100"
      find("summary", text: /details/i).click
      check "Shared expenses"
      click_button "Add transaction"
      assert_text "Transaction created"
      entry = accounts(:depository).entries.find_by!(name: "Shared #{nature}")
      assert entry.transaction.shared_expense?
      assert_equal nature == "outflow" ? 100 : -100, entry.amount

      visit transaction_url(entry)
      find("summary", text: /settings/i).click
      assert_checked_field "Shared expenses"
      page.execute_script <<~JS
        const input = document.querySelector("input[type='checkbox'][name='entry[entryable_attributes][shared_expense]']");
        input.form.addEventListener("turbo:submit-end", (event) => {
          if (event.detail.success) input.form.dataset.testSaved = "true";
        }, { once: true });
      JS
      uncheck "Shared expenses"
      assert_selector "form[data-test-saved='true']"
      assert_not entry.transaction.reload.shared_expense?
    end
  end

  test "details offers both classifications immediately above notes and shared rows have an indicator" do
    visit new_transaction_url(account_id: accounts(:depository).id)
    fill_in "Description", with: "One-time shared purchase"
    fill_in "entry_amount", with: "100"
    assert_no_selector "input[type=checkbox][name='entry[entryable_attributes][shared_expense]']", visible: true
    find("summary", text: /details/i).click
    check "Shared expenses"
    check "One-time expense"
    fill_in "entry_notes", with: "Keep this note"
    click_button "Add transaction"
    assert_text "Transaction created"
    entry = accounts(:depository).entries.find_by!(name: "One-time shared purchase")
    assert entry.transaction.shared_expense?
    assert entry.transaction.forecast_exceptional_once?
    assert_equal "Keep this note", entry.notes
    visit transactions_url
    within "##{ActionView::RecordIdentifier.dom_id(entry)}" do
      assert_selector "[role=img][aria-label='Shared expenses'][title='Shared expenses']"
    end
  end
end
