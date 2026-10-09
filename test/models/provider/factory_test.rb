require "test_helper"

class Provider::FactoryTest < ActiveSupport::TestCase
  test "resolves only Enable Banking without adapter self registration" do
    assert_equal [ "EnableBankingAccount" ], Provider::Factory.registered_provider_types
    assert_equal [ Provider::EnableBankingAdapter ], Provider::Factory.registered_adapters
    assert Provider::Factory.registered?("EnableBankingAccount")
    assert_not Provider::Factory.registered?("UnknownAccount")
  end

  test "passes the bank account and explicit financial account to the adapter" do
    provider_account = EnableBankingAccount.new
    account = accounts(:depository)
    adapter = Provider::Factory.create_adapter(provider_account, account: account)

    assert_instance_of Provider::EnableBankingAdapter, adapter
    assert_same provider_account, adapter.provider_account
    assert_same account, adapter.account

    link = AccountProvider.new(account: account, provider: provider_account)
    assert_same account, Provider::Factory.from_account_provider(link).account
  end

  test "nil connections remain optional and unknown types fail explicitly" do
    assert_nil Provider::Factory.create_adapter(nil)
    assert_nil Provider::Factory.from_account_provider(nil)
    error = assert_raises(Provider::Factory::AdapterNotFoundError) do
      Provider::Factory.create_adapter(accounts(:depository))
    end
    assert_includes error.message, "Account"
  end

  test "supports deposits and cards while refusing investment connectors" do
    assert Provider::Factory.supports_account_type?("Depository")
    assert Provider::Factory.supports_account_type?("CreditCard")
    assert_not Provider::Factory.supports_account_type?("Investment")
    assert_not Provider::Factory.supports_account_type?("Crypto")
  end

  test "connection configuration still respects family availability" do
    family = families(:dylan_family)
    family.stubs(:can_connect_enable_banking?).returns(false)
    assert_empty Provider::Factory.connection_configs_for_account_type(account_type: "Depository", family: family)

    family.stubs(:can_connect_enable_banking?).returns(true)
    configs = Provider::Factory.connection_configs_for_account_type(account_type: "Depository", family: family)
    assert_equal [ "enable_banking" ], configs.map { |config| config[:key] }
    assert_empty Provider::Factory.connection_configs_for_account_type(account_type: "Investment", family: family)
  end
end
