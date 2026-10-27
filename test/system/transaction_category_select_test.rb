require "application_system_test_case"

class TransactionCategorySelectTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
  end

  test "members can choose global categories but cannot create one inline" do
    sign_in users(:family_member)
    visit new_transaction_url
    within "[data-controller='category-select']" do
      find("button", match: :first).click
      assert_text categories(:food_and_drink).name
      fill_in "Search categories", with: "Member cannot create this category"
      assert_no_selector "[data-category-select-target='createForm']", visible: true
    end
  end

  test "can create a category from the transaction form" do
    visit new_transaction_url

    assert_difference "Category.count", +1 do
      find("[data-controller='category-select'] button").click

      within "[data-controller='category-select']" do
        fill_in "Search categories", with: "Inline Test Category"

        assert_text 'Create "Inline Test Category"'
        click_button 'Create "Inline Test Category"'

        assert_selector(
          "[data-category-select-target='option'][aria-selected='true']",
          text: "Inline Test Category",
          visible: :all
        )
      end
    end

    assert Category.exists?(name: "Inline Test Category")
  end

  test "shows subcategories nested under their parent" do
    subcategory = categories(:subcategory)

    visit new_transaction_url

    within "[data-controller='category-select']" do
      find("button", match: :first).click

      nested_option = find("[role='option'][data-category-id='#{subcategory.id}']")

      assert nested_option.has_selector?("[data-testid='category-select-subcategory-indicator']")
      assert_equal subcategory.display_name_with_parent,
                   nested_option["data-category-search-name"]
      assert_text subcategory.display_name
    end
  end

  test "can clear a category from an existing transaction" do
    transaction = transactions(:one)
    transaction.update!(category: categories(:food_and_drink))
    entry = transaction.entry

    visit transactions_url

    page.execute_script <<~JS
      const frame = document.querySelector("turbo-frame#drawer")
      frame.src = "#{transaction_url(entry)}"
    JS

    within "turbo-frame#drawer", visible: :all do
      assert_selector "[data-controller='category-select']"

      within "[data-controller='category-select']" do
        find("button", match: :first).click
        find("button[data-category-id='']").click
      end
    end

    assert_selector(
      "##{ActionView::RecordIdentifier.dom_id(entry)}",
      text: "Uncategorized"
    )

    assert_nil transaction.reload.category_id
  end
end
