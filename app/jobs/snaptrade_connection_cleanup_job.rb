# Consumer for jobs serialized before connector retirement.
class SnaptradeConnectionCleanupJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled SnaptradeConnectionCleanupJob: account connector retired")
  end
end
