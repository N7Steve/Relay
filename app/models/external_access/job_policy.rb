class ExternalAccess::JobPolicy
  BANK_JOBS = %w[
    SyncAllJob SyncAllProvidersJob SyncHourlyJob FinancekitInboxJob
    TradeRepublicRepairJob SophtronRefreshPollJob SophtronInitialLoadJob
    SnaptradeFollowUpSyncJob SnaptradeConnectionCleanupJob SnaptradeActivitiesFetchJob
    SimplefinItem::BalancesOnlyJob SimplefinHoldingsApplyJob SimplefinConnectionUpdateJob
    RedbarkConnectionCleanupJob QuestradeActivitiesFetchJob
    PlaidTransactionsRefreshPollJob PlaidTransactionsRefreshJob
    PlaidTransactionsRefreshFollowUpSyncJob PlaidTransactionsRefreshAllJob PlaidFollowUpSyncJob
    IndexaCapitalConnectionCleanupJob IndexaCapitalActivitiesFetchJob
  ].freeze

  def self.capability(job_name)
    return :bank_sync if BANK_JOBS.include?(job_name)
    return :market_data if %w[ImportMarketDataJob SecurityHealthCheckJob YahooFinanceHealthCheckJob].include?(job_name)
    return :property_valuations if job_name == "SyncPropertyValuationsJob"
    :google_drive if %w[DispatchGoogleDriveExportsJob GoogleDriveExportJob].include?(job_name)
  end
end
