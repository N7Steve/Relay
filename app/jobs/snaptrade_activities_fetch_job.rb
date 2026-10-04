# Consumer for jobs serialized before connector retirement.
class SnaptradeActivitiesFetchJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled SnaptradeActivitiesFetchJob: account connector retired")
  end
end
