require "test_helper"

class Account::FamilyManagedTest < ActiveSupport::TestCase
  setup do
    @manager = users(:family_member)
    @manager.update!(role: :super_admin)
    @partner = users(:family_admin)
    @partner_account = accounts(:investment)
    @shared_account = accounts(:depository)
  end

  test "a super admin manages family accounts that are neither owned nor shared" do
    managed = Account.family_managed_by(@manager)

    assert_includes managed, @partner_account
    assert_not_includes managed, @shared_account
    assert @partner_account.family_managed_by?(@manager)
    assert_not @shared_account.family_managed_by?(@manager)
  end

  test "family-managed accounts stay out of personal and finance scopes" do
    assert_not_includes Account.accessible_by(@manager), @partner_account
    assert_not_includes @manager.finance_accounts, @partner_account
    assert_not_includes Account.writable_by(@manager), @partner_account
    assert_includes @manager.reachable_accounts, @partner_account
    assert_includes @manager.reachable_accounts, @shared_account
  end

  test "the manager operates family accounts with full control but cannot delete them" do
    assert_equal :full_control, @partner_account.permission_for(@manager)
    assert @partner_account.shared_with?(@manager)
    assert AccountPolicy.new(@manager, @partner_account).update?
    assert_not AccountPolicy.new(@manager, @partner_account).destroy?
  end

  test "an explicit share keeps its own permission and finance choice" do
    assert_equal :full_control, @shared_account.permission_for(@manager)
    assert_equal :read_only, accounts(:credit_card).permission_for(@manager)
    assert_includes @manager.finance_accounts, @shared_account
  end

  test "members and admins do not manage the accounts of others" do
    member = users(:family_member)
    member.update!(role: :member)
    admin_owned = accounts(:investment)

    assert_empty Account.family_managed_by(member)
    assert_not admin_owned.family_managed_by?(member)
    assert_nil admin_owned.permission_for(member)

    manager_account = Account.create!(
      family: member.family, owner: @partner, name: "Admin savings", balance: 10, currency: "USD",
      accountable: Depository.new
    )
    assert_empty Account.family_managed_by(@partner)
    assert_not manager_account.family_managed_by?(@partner)
  end

  test "a super admin of another family does not reach this family's accounts" do
    outsider = users(:sure_support_staff)

    assert outsider.family_manager?
    assert_not_includes Account.family_managed_by(outsider), @partner_account
    assert_not @partner_account.family_managed_by?(outsider)
  end

  test "an inactive super admin loses family access" do
    # Deactivation guards are covered elsewhere; only the access rule matters here.
    @manager.update_column(:active, false)

    assert_not @manager.reload.family_manager?
    assert_empty Account.family_managed_by(@manager)
  end

  test "the family accounts preference defaults on and can be turned off" do
    assert @manager.show_family_accounts?

    @manager.update_show_family_accounts!("0")
    assert_not @manager.reload.show_family_accounts?

    @manager.update_show_family_accounts!("1")
    assert @manager.reload.show_family_accounts?
  end
end
