# Consumer for jobs serialized before connector retirement.
class SnaptradeFollowUpSyncJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled SnaptradeFollowUpSyncJob: account connector retired")
  end
end
