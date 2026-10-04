require "test_helper"

class ProviderItemOwnableTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @admin  = users(:family_admin)
    @member = users(:family_member)
    Current.reset
  end

  teardown { Current.reset }

  # An anonymous model that includes the concern without declaring a scope,
  # standing in for any of the 24 providers that have not been classified yet.
  def undeclared_item_class
    Class.new(ApplicationRecord) do
      self.table_name = "plaid_items"
      belongs_to :family
      include ProviderItemOwnable

      def self.name = "UndeclaredItem"
    end
  end

  test "credential scope defaults to tenant_wide so an unclassified provider stays admin-only" do
    klass = undeclared_item_class

    assert_equal :tenant_wide, klass.declared_credential_scope
    assert_not klass.member_connectable?
  end

  test "credential scope rejects an unknown value" do
    error = assert_raises(ArgumentError) { undeclared_item_class.credential_scope(:sometimes) }
    assert_match(/unknown credential scope/, error.message)
  end
end
