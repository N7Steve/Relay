# Consumer for jobs serialized before connector retirement.
class PlaidTransactionsRefreshFollowUpSyncJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled PlaidTransactionsRefreshFollowUpSyncJob: account connector retired")
  end
end
