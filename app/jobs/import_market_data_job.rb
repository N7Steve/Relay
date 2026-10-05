# Compatibility sink for serialized jobs from before pruning phase 9A.
class ImportMarketDataJob < ApplicationJob
  queue_as :scheduled

  def perform(opts = {})
    Rails.logger.info("[RetiredMarketData] Ignored ImportMarketDataJob")
  end
end
