require "test_helper"

class BalanceSheet::SyncStatusMonitorTest < ActiveSupport::TestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @family = families(:dylan_family)
    @account = accounts(:depository)
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "a sync that starts and completes within the same second does not stay syncing" do
    started_at = Time.zone.parse("2026-11-21 22:38:12.269")
    sync = @account.syncs.create!(status: "syncing")
    @family.update_column(:latest_sync_activity_at, started_at)

    assert BalanceSheet::SyncStatusMonitor.new(@family.reload).account_syncing?(@account)

    sync.update_column(:status, "completed")
    @family.update_column(:latest_sync_activity_at, started_at + 0.195.seconds)

    assert_not BalanceSheet::SyncStatusMonitor.new(@family.reload).account_syncing?(@account)
  end

  test "a cached syncing set expires with the visible window" do
    sync = @account.syncs.create!(status: "syncing")

    assert BalanceSheet::SyncStatusMonitor.new(@family.reload).account_syncing?(@account)

    sync.update_column(:status, "completed")

    travel Sync::VISIBLE_FOR + 1.second do
      assert_not BalanceSheet::SyncStatusMonitor.new(@family.reload).account_syncing?(@account)
    end
  end
end
