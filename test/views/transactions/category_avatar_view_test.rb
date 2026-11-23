require "test_helper"

class Transactions::CategoryAvatarViewTest < ActionView::TestCase
  setup do
    Current.session = Session.create!(user: users(:family_admin))
    @account = accounts(:depository)
  end

  test "a movement without a merchant logo shows its category instead of an initial" do
    category = categories(:food_and_drink)
    category.update!(lucide_icon: "utensils", color: "#e99537")

    html = render_row(name: "Zeta Bistro", category: category)
    avatar = Nokogiri::HTML.fragment(html).at_css("[data-testid='transaction-category-avatar'] [role='img']")

    assert_equal category.display_name, avatar["aria-label"]
    assert_includes avatar["style"], "#e99537"
    assert_nil avatar.at_css("span"), "the name's initial should no longer be rendered"
  end

  test "an uncategorized movement shows the uncategorized mark" do
    html = render_row(name: "Zeta Bistro", category: nil)
    avatar = Nokogiri::HTML.fragment(html).at_css("[data-testid='transaction-category-avatar'] [role='img']")

    assert_equal Category.uncategorized.display_name, avatar["aria-label"]
    assert_includes avatar["style"], Category::UNCATEGORIZED_COLOR
  end

  private
    def render_row(name:, category:)
      entry = Entry.create!(account: @account, entryable: Transaction.create!(category: category), name: name,
        amount: 12, currency: "USD", date: Date.current)
      render(partial: "transactions/transaction", locals: { entry: entry, balance_trend: nil, view_ctx: "global" })
    end
end
