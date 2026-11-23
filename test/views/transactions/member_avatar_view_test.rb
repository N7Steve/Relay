require "test_helper"

class Transactions::MemberAvatarViewTest < ActionView::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @member = users(:family_member)
    Current.session = Session.create!(user: @user)
    @shared = accounts(:depository)
  end

  test "a transfer from another member's account shows that member instead of the transfer icon" do
    partner = @family.accounts.create!(name: "Partner checking", balance: 0, currency: "USD",
      accountable: Depository.new, owner: @member)
    inflow = transfer_between(from: partner, to: @shared).inflow_transaction

    avatar = Nokogiri::HTML.fragment(render_row(inflow.entry)).at_css("[data-testid='transaction-member-avatar']")

    assert_not_nil avatar
    assert_equal @member.display_name, avatar["title"]
    assert_includes avatar.text, @member.initial
  end

  test "the user's own transfers keep the transfer icon" do
    inflow = transfer_between(from: accounts(:credit_card), to: @shared).inflow_transaction

    html = render_row(inflow.entry)

    assert_nil Nokogiri::HTML.fragment(html).at_css("[data-testid='transaction-member-avatar']")
  end

  private
    def transfer_between(from:, to:)
      outflow = Transaction.create!(kind: "funds_movement")
      Entry.create!(account: from, entryable: outflow, name: "Transfer out", amount: 100, currency: "USD", date: Date.current)
      inflow = Transaction.create!(kind: "funds_movement")
      Entry.create!(account: to, entryable: inflow, name: "Transfer in", amount: -100, currency: "USD", date: Date.current)
      Transfer.create!(inflow_transaction: inflow, outflow_transaction: outflow, status: "confirmed")
    end

    def render_row(entry)
      render(partial: "transactions/transaction", locals: { entry: entry, balance_trend: nil, view_ctx: "global" })
    end
end
