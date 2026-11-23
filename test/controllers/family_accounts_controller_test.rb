require "test_helper"

class FamilyAccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:family_member)
    @manager.update!(role: :super_admin)
    @partner = users(:family_admin)
    @partner_account = accounts(:investment)
  end

  test "a super admin sees the family accounts grouped by member" do
    sign_in @manager

    get family_accounts_url

    assert_response :success
    assert_select "[data-testid=family-member]", text: /#{Regexp.escape(@partner.display_name)}/
    assert_select "main a[href=?]", account_path(@partner_account)
    assert_select "main a[href=?]", account_path(accounts(:depository)), count: 0
  end

  test "members cannot open the Family section" do
    sign_in @partner

    get family_accounts_url

    assert_redirected_to root_url
  end

  test "the toggle hides and shows the sidebar Family group" do
    sign_in @manager

    get sidebar_accounts_url
    assert_select "[data-testid=family-accounts-sidebar] a[href=?]", account_path(@partner_account)

    patch family_accounts_url, params: { show_family_accounts: "0" }
    assert_redirected_to family_accounts_url
    assert_not @manager.reload.show_family_accounts?

    get sidebar_accounts_url
    assert_select "[data-testid=family-accounts-sidebar]", count: 0

    patch family_accounts_url, params: { show_family_accounts: "1" }
    assert @manager.reload.show_family_accounts?
  end

  test "a super admin opens and edits a family account" do
    sign_in @manager

    get account_url(@partner_account)
    assert_response :success
    assert_includes response.body, ERB::Util.html_escape(I18n.t("family_accounts.account_notice", owner: @partner.display_name))

    entry = @partner_account.entries.transactions.first || create_partner_transaction
    patch transaction_url(entry), params: { entry: { name: "Edited by family manager" } }

    assert_equal "Edited by family manager", entry.reload.name
  end

  test "a super admin adds a transaction to a family account from its page" do
    partner_checking = Account.create!(
      family: @partner.family, owner: @partner, name: "Partner checking", balance: 500, currency: "USD",
      accountable: Depository.new
    )
    sign_in @manager

    get new_transaction_url(account_id: partner_checking.id)
    assert_response :success
    assert_includes response.body, partner_checking.name

    assert_difference -> { partner_checking.entries.count }, 1 do
      post transactions_url, params: { entry: { account_id: partner_checking.id, name: "Family groceries",
        date: Date.current, currency: "USD", amount: 20, nature: "outflow", entryable_type: "Transaction",
        entryable_attributes: { shared_expense: "0" } } }
    end
    assert_redirected_to account_url(partner_checking)
  end

  test "the member partner cannot open the super admin's accounts" do
    own_account = Account.create!(
      family: @manager.family, owner: @manager, name: "Manager savings", balance: 100, currency: "USD",
      accountable: Depository.new
    )
    sign_in @partner

    get account_url(own_account)

    assert_response :not_found
  end

  test "family accounts stay out of the manager's transactions list" do
    entry = create_partner_transaction(name: "Partner only purchase")
    sign_in @manager

    get transactions_url

    assert_response :success
    assert_no_match entry.name, response.body
  end

  private
    def create_partner_transaction(name: "Partner purchase")
      @partner_account.entries.create!(
        name: name, date: Date.current, amount: 12, currency: @partner_account.currency,
        entryable: Transaction.new
      )
    end
end
