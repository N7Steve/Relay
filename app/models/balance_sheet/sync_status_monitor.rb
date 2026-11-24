class BalanceSheet::SyncStatusMonitor
  def initialize(family)
    @family = family
  end

  def syncing?
    syncing_account_ids.any?
  end

  def account_syncing?(account)
    syncing_account_ids.include?(account.id)
  end

  private
    attr_reader :family

    # The entry expires with the visible window so a set cached mid-sync can never outlive it.
    def syncing_account_ids
      @syncing_account_ids ||= Rails.cache.fetch(cache_key, expires_in: Sync::VISIBLE_FOR) do
        Sync.visible
            .where(syncable_type: "Account", syncable_id: family.accounts.sync_enabled.select(:id))
            .pluck(:syncable_id)
            .to_set
      end
    end

    # We re-fetch the set of syncing IDs any time a sync that belongs to the family is started or completed.
    # This ensures we're always fetching the latest sync statuses without re-querying on every page load in idle times (no syncs happening).
    # Microsecond precision matters: a fast sync is created, started and completed within one second, and a
    # second-resolution key would keep serving the set cached while it ran.
    def cache_key
      [
        "balance_sheet_sync_status",
        family.id,
        family.latest_sync_activity_at&.utc&.iso8601(6)
      ].join("_")
    end
end
