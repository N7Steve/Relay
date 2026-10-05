# Compatibility sink for serialized jobs from before pruning phase 9F.
class FinancekitPurgeJob < ApplicationJob
  queue_as :low_priority

  def perform(item)
    Rails.logger.info("[RetiredFinanceKit] Ignored FinancekitPurgeJob")
  end
end
