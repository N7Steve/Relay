# Consumer for jobs serialized before connector retirement.
class SimplefinHoldingsApplyJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled SimplefinHoldingsApplyJob: account connector retired")
  end
end
