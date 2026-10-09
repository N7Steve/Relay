require "test_helper"

class Family::FinancialInventoryTest < ActiveSupport::TestCase
  include EntriesTestHelper

  test "inventory reports legacy policy counts without modifying rows or exposing financial values" do
    family = families(:empty)
    account = family.accounts.create!(name: "Private account", accountable: Investment.new(subtype: "401k"), currency: "USD", balance: 15_000)
    entry = create_transaction(account: account)
    entry.update_columns(excluded: true, import_protected: nil)
    entry.entryable.update_columns(kind: "one_time", posting_status: nil, extra: { "plaid" => { "pending" => true }, "enable_banking" => { "pending" => false } })
    before = entry.reload.attributes

    report = Family::FinancialInventory.new(family).call

    assert_equal 1, report[:implicit_import_protection]
    assert_equal 1, report[:legacy_one_time]
    assert_equal 1, report[:conflicting_pending_flags]
    assert_equal({ "401k" => 1 }, report[:investments_by_subtype])
    assert_equal before, entry.reload.attributes
    assert_not_includes report.to_json, "Private account"
    assert_not_includes report.to_json, entry.id
  end
end
