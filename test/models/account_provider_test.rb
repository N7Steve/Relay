require "test_helper"

class AccountProviderTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:depository)
    @family = families(:dylan_family)

    @plaid_account = enable_banking_accounts(:one)
    @simplefin_account = enable_banking_accounts(:two)
  end

  test "prevents duplicate provider type for same account" do
    # Create first PlaidAccount link
    AccountProvider.create!(
      account: @account,
      provider: @plaid_account
    )

    # Create another PlaidAccount
    another_plaid_account = enable_banking_accounts(:two)

    # Should not be able to link another PlaidAccount to same account
    duplicate_provider = AccountProvider.new(
      account: @account,
      provider: another_plaid_account
    )

    assert_not duplicate_provider.valid?
    assert_includes duplicate_provider.errors[:account_id], "has already been taken"
  end

  test "prevents same provider account from linking to multiple accounts" do
    # Link provider to first account
    AccountProvider.create!(
      account: @account,
      provider: @plaid_account
    )

    # Try to link same provider to another account
    another_account = accounts(:investment)

    duplicate_link = AccountProvider.new(
      account: another_account,
      provider: @plaid_account
    )

    assert_not duplicate_link.valid?
    assert_includes duplicate_link.errors[:provider_id], "has already been taken"
  end

  test "adapter method returns correct adapter" do
    provider = AccountProvider.create!(
      account: @account,
      provider: @plaid_account
    )

    assert_kind_of Provider::EnableBankingAdapter, provider.adapter
  end

  test "historical provider_name uses its stable local type" do
    plaid_provider = AccountProvider.create!(
      account: @account,
      provider: @plaid_account
    )

    simplefin_provider = AccountProvider.create!(
      account: accounts(:investment),
      provider: @simplefin_account
    )

    assert_equal "enable_banking", plaid_provider.provider_name
    assert_equal "enable_banking", simplefin_provider.provider_name
  end
end
