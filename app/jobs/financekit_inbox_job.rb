# Compatibility sink for serialized jobs from before pruning phase 9F.
class FinancekitInboxJob < ApplicationJob
  queue_as :high_priority

  def perform(item_id = nil)
    Rails.logger.info("[RetiredFinanceKit] Ignored FinancekitInboxJob")
  end
end
