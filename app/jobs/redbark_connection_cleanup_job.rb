# Consumer for jobs serialized before connector retirement.
class RedbarkConnectionCleanupJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled RedbarkConnectionCleanupJob: account connector retired")
  end
end
