# Consumer for the retired hourly connector schedule.
class SyncHourlyJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled SyncHourlyJob: account connectors retired")
  end
end
