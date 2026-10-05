require "test_helper"

class Account::LinkableTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
  end

  test "linked? returns true when account has providers" do
    plaid_account = enable_banking_accounts(:one)
    AccountProvider.create!(account: @account, provider: plaid_account)

    assert @account.linked?
  end

  test "linked? returns false when account has no providers" do
    assert @account.unlinked?
  end

  test "providers returns all provider adapters" do
    plaid_account = enable_banking_accounts(:one)
    AccountProvider.create!(account: @account, provider: plaid_account)

    providers = @account.providers
    assert_equal 1, providers.count
    assert_kind_of Provider::EnableBankingAdapter, providers.first
  end

  test "provider_for returns specific provider adapter" do
    plaid_account = enable_banking_accounts(:one)
    AccountProvider.create!(account: @account, provider: plaid_account)

    adapter = @account.provider_for("EnableBankingAccount")
    assert_kind_of Provider::EnableBankingAdapter, adapter
  end

  test "linked_to? checks if account is linked to specific provider type" do
    plaid_account = enable_banking_accounts(:one)
    AccountProvider.create!(account: @account, provider: plaid_account)

    assert @account.linked_to?("EnableBankingAccount")
    refute @account.linked_to?("SimplefinAccount")
  end



  test "supports_category_matcher? returns false for unlinked accounts and providers without a matcher" do
    refute @account.supports_category_matcher?

    @account.account_providers.create!(provider: enable_banking_accounts(:one))

    refute @account.supports_category_matcher?
  end

  test "can_delete_holdings? returns true for unlinked accounts" do
    assert @account.unlinked?
    assert @account.can_delete_holdings?
  end

  test "can_delete_holdings? returns false when any provider disallows deletion" do
    plaid_account = enable_banking_accounts(:one)
    AccountProvider.create!(account: @account, provider: plaid_account)

    # PlaidAdapter.can_delete_holdings? returns false by default
    refute @account.can_delete_holdings?
  end

  test "can_delete_holdings? returns true only when all providers allow deletion" do
    plaid_account = enable_banking_accounts(:one)
    AccountProvider.create!(account: @account, provider: plaid_account)

    # Stub all providers to return true
    @account.providers.each do |provider|
      provider.stubs(:can_delete_holdings?).returns(true)
    end

    assert @account.can_delete_holdings?
  end

  # The `linked` scope mirrors `linked?` at the SQL level. These tests pin
  # all three link types so a future schema or `linked?` change breaks the
  # test instead of silently diverging (e.g. wrong sparkline aggregation).
  test "linked scope matches accounts linked via account_providers" do
    plaid_account = enable_banking_accounts(:one)
    AccountProvider.create!(account: @account, provider: plaid_account)

    assert_includes Account.linked, @account
  end



  test "linked scope excludes manual accounts" do
    assert @account.unlinked?
    refute_includes Account.linked, @account
  end
end
