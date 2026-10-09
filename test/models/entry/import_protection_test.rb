require "test_helper"

class Entry::ImportProtectionTest < ActiveSupport::TestCase
  include EntriesTestHelper

  test "analytical exclusion and import protection are independent for new movements" do
    entry = create_transaction(excluded: true)
    assert_not entry.protected_from_sync?
    assert_not entry.import_protected?

    entry.update!(import_protected: true, excluded: false)
    assert entry.protected_from_sync?
    assert_equal :import_protected, entry.protection_reason
    assert Entry.eligible_for_forecast_history.exists?(entry.id)
  end

  test "legacy protection survives analytical edits and only explicit unlock clears it" do
    entry = create_transaction
    entry.update_columns(import_protected: nil, excluded: true)
    assert entry.reload.protected_from_sync?

    entry.update!(excluded: false)
    assert entry.reload.import_protected?
    entry.update!(excluded: true, user_modified: true, import_locked: true)
    entry.unlock_for_sync!
    assert entry.reload.excluded?
    assert_not entry.protected_from_sync?
  end

  test "provider updates an analytically excluded unlocked movement but preserves explicit protection" do
    adapter = Account::ProviderImportAdapter.new(accounts(:depository))
    arguments = { external_id: "independent-exclusion", amount: 100, currency: "USD", date: Date.current, name: "Bank", source: "enable_banking" }
    entry = adapter.import_transaction(**arguments)
    entry.update!(excluded: true)
    adapter.import_transaction(**arguments.merge(amount: 200))
    assert_equal 200, entry.reload.amount
    assert entry.excluded?

    entry.update!(import_protected: true)
    adapter.import_transaction(**arguments.merge(amount: 300))
    assert_equal 200, entry.reload.amount
  end
end
