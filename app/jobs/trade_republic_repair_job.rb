# Consumer for jobs serialized before connector retirement.
class TradeRepublicRepairJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled TradeRepublicRepairJob: account connector retired")
  end
end
