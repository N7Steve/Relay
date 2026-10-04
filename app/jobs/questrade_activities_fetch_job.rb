# Consumer for jobs serialized before connector retirement.
class QuestradeActivitiesFetchJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled QuestradeActivitiesFetchJob: account connector retired")
  end
end
