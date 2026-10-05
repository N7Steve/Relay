require "test_helper"

class RetiredAccountConnectorTest < ActiveSupport::TestCase
  test "retired connector credentials cannot recreate runtime providers or routes" do
    RetiredAccountConnector::PREFIXES.each do |prefix|
      key = prefix.underscore
      assert_nil "Provider::#{prefix}".safe_constantize
      assert_nil "Provider::#{prefix}Adapter".safe_constantize
      assert_not Provider::Factory.registered?("#{prefix}Account")
      assert_not "#{prefix}Item".constantize.included_modules.include?(Syncable)
      assert_not Rails.application.routes.routes.any? { |route| route.defaults[:controller] == "#{key}_items" }
    end
    assert_empty Rails.application.routes.routes.select { |route| route.defaults[:controller].to_s.start_with?("webhooks/") }
    assert Provider::Factory.registered?("EnableBankingAccount")
    assert_not Provider::Factory.registered?("FinancekitAccountLineage")
    assert_equal "enable_banking_items", Rails.application.routes.recognize_path("/enable_banking_items/callback", method: :get)[:controller]
  end

  test "an old serialized sync is finalized without importing or deleting historical data" do
    item = plaid_items(:one)
    original = item.attributes
    parent = Sync.create!(syncable: item.family, status: "syncing")
    sync = Sync.create!(syncable: item, parent: parent)
    SyncJob.perform_now(sync)

    assert sync.reload.stale?
    assert_equal "Account connector retired", sync.error
    assert parent.reload.completed?
    assert_equal original, item.reload.attributes
    assert_nil Provider::Factory.create_adapter(plaid_accounts(:one))
  end

  test "serialized connector destruction preserves the record and its original" do
    item = plaid_items(:one)
    before = item.attributes
    DestroyJob.perform_now(item)
    assert_equal before, item.reload.attributes
  end

  test "retired sync cancellation cancels pending descendants without importing" do
    item = plaid_items(:one)
    sync = Sync.create!(syncable: item)
    child = Sync.create!(syncable: accounts(:connected), parent: sync)
    Account.any_instance.expects(:perform_sync).never
    SyncJob.perform_now(sync)
    SyncJob.perform_now(child.reload)
    assert sync.reload.stale?
    assert child.reload.stale?
  end

  test "family sync discovery includes only retained connector items" do
    families(:dylan_family).plaid_items.each do |item|
      assert_not item.respond_to?(:sync_later)
    end
    retained = Family.reflect_on_all_associations(:has_many).select do |association|
      association.name.to_s.end_with?("_items") && association.klass.included_modules.include?(Syncable)
    end
    assert_equal %i[enable_banking_items], retained.map(&:name).sort
  end
end
