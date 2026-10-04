# Consumer for jobs serialized before connector retirement.
class IndexaCapitalConnectionCleanupJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled IndexaCapitalConnectionCleanupJob: account connector retired")
  end
end
