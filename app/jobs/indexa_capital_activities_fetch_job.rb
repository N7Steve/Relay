# Consumer for jobs serialized before connector retirement.
class IndexaCapitalActivitiesFetchJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled IndexaCapitalActivitiesFetchJob: account connector retired")
  end
end
