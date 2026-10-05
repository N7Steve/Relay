# Compatibility sink for serialized jobs from before pruning phase 9A.
class SecurityHealthCheckJob < ApplicationJob
  queue_as :scheduled

  def perform
    Rails.logger.info("[RetiredMarketData] Ignored SecurityHealthCheckJob")
  end
end
