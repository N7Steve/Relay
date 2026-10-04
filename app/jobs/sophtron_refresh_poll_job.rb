# Consumer for jobs serialized before connector retirement.
class SophtronRefreshPollJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled SophtronRefreshPollJob: account connector retired")
  end
end
