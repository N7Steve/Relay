# Consumer for jobs serialized before connector retirement.
class PlaidFollowUpSyncJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled PlaidFollowUpSyncJob: account connector retired")
  end
end
