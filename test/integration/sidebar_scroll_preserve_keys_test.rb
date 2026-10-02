require "test_helper"

class SidebarScrollPreserveKeysTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "sidebar scroll uses its persistent Stimulus controller" do
    get root_path

    assert_response :ok
    assert_select "#sidebar-scroll[data-controller~='preserve-scroll']"
  end

  test "every account type has a user-scoped persisted disclosure" do
    Accountable::TYPES.each do |type|
      @user.family.accounts.create!(
        name: "Sidebar #{type}", owner: @user, currency: "USD", balance: 0,
        accountable: type.constantize.new
      )
    end

    get sidebar_accounts_path

    assert_response :ok
    Accountable::TYPES.each do |type|
      assert_select "details[data-controller~='persisted-disclosure'][data-persisted-disclosure-key-value$='-#{type.underscore}']" do |elements|
        elements.each do |element|
          assert_includes element["data-persisted-disclosure-key-value"], @user.id
          assert_includes element["data-action"], "turbo:before-morph-attribute->persisted-disclosure#preserveOpen"
        end
      end
    end
  end
end
