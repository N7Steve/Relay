# Consumer for jobs serialized before connector retirement.
class SimplefinConnectionUpdateJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled SimplefinConnectionUpdateJob: account connector retired")
  end
end
