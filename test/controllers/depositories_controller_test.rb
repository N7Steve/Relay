require "test_helper"

class DepositoriesControllerTest < ActionDispatch::IntegrationTest
  include AccountableResourceInterfaceTest

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:depository)
  end

  test "create falls back to the stored return_to when no form param is present" do
    get new_account_path(return_to: transactions_path) # StoreLocation captures it into the session

    assert_difference -> { Account.count } => 1 do
      post depositories_path, params: {
        account: { name: "Return To Checking", currency: "USD", balance: 100, accountable_type: "Depository" }
      }
    end

    assert_redirected_to transactions_path
  end

  test "create prefers the form return_to over the session value" do
    get new_account_path(return_to: transactions_path) # session return_to

    post depositories_path, params: {
      account: { name: "Form RT Checking", currency: "USD", balance: 100, accountable_type: "Depository", return_to: budgets_path }
    }

    assert_redirected_to budgets_path
  end

  test "create ignores an external return_to (open-redirect guard)" do
    post depositories_path, params: {
      account: { name: "Evil RT Checking", currency: "USD", balance: 100, accountable_type: "Depository", return_to: "https://evil.example/phish" }
    }

    created = Account.order(:created_at).last
    assert_redirected_to account_path(created) # not the external URL
  end

  test "update persists enable_category_matcher through the shared update action" do
    linked_account = accounts(:connected)
    assert linked_account.enable_category_matcher?

    patch depository_path(linked_account), params: {
      account: { enable_category_matcher: "0" }
    }

    refute linked_account.reload.enable_category_matcher?

    patch depository_path(linked_account), params: {
      account: { enable_category_matcher: "1" }
    }

    assert linked_account.reload.enable_category_matcher?
  end

  test "edit form renders category matcher toggle only for accounts that support it" do
    get edit_account_url(accounts(:connected))
    assert_response :success
    assert_select "input[type=checkbox][name='account[enable_category_matcher]']", 0

    get edit_account_url(accounts(:depository))
    assert_response :success
    assert_select "input[name='account[enable_category_matcher]']", 0
  end

  test "edit form shows custom cash subtypes and financial treatment outside additional details" do
    get edit_account_url(@account)

    assert_response :success
    %w[payroll mortgage investment asset].each do |subtype|
      assert_select "select[name='account[subtype]'] option[value='#{subtype}']", 1
    end
    assert_select "select[name='account[financial_treatment]']", 1
    assert_select "details select[name='account[financial_treatment]']", 0
  end

  test "an invalid account update preserves its balance and custom logo" do
    @account.custom_logo.attach(fixture_file_upload("profile_image.png", "image/png", :binary))
    balance = @account.balance
    logo_id = @account.custom_logo.blob.id

    assert_no_difference "Valuation.count" do
      patch depository_path(@account), params: {
        account: { name: "", balance: balance + 100, delete_custom_logo: "1" }
      }
    end

    assert_response :unprocessable_entity
    assert_equal balance, @account.reload.balance
    assert_equal logo_id, @account.custom_logo.blob.id
  end

  test "update attaches and removes a custom account logo" do
    patch depository_path(@account), params: {
      account: {
        custom_logo: fixture_file_upload("profile_image.png", "image/png", :binary)
      }
    }

    assert_redirected_to account_path(@account)
    assert @account.reload.custom_logo.attached?

    patch depository_path(@account), params: {
      account: { delete_custom_logo: "1" }
    }

    assert_redirected_to account_path(@account)
    assert_not @account.reload.custom_logo.attached?
  end

  # --- member-owned connections (issue #3579) ------------------------------

  test "a member is not offered the family-wide Enable Banking connector" do
    sign_in users(:family_member)
    get new_depository_path(step: "method_select")
    assert_response :success
    assert_select "a[href*=?]", "enable_banking", count: 0
  end
  test "an admin can connect Enable Banking from the method selector" do
    sign_in users(:family_admin)
    get new_depository_path(step: "method_select")
    assert_response :success
    assert_select "a[href=?]", new_enable_banking_item_path(accountable_type: "Depository"), count: 1
  end
  test "a member is offered manual entry even with no connectable providers" do
    Family.any_instance.stubs(:can_connect_plaid_us?).returns(false)
    Family.any_instance.stubs(:can_connect_plaid_eu?).returns(false)

    sign_in users(:family_member)
    get new_depository_path(step: "method_select")

    assert_response :success
    assert_select "a[href=?]", new_depository_path, count: 1
  end
end
