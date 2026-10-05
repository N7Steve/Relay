# Compatibility sink for serialized jobs from before pruning phase 9A.
class YahooFinanceHealthCheckJob < ApplicationJob
  def perform
    Rails.logger.info("[RetiredMarketData] Ignored YahooFinanceHealthCheckJob")
  end
end
