# Compatibility sink for serialized jobs from before pruning phase 8.
class IdentifyRecurringTransactionsJob < ApplicationJob
  queue_as :default

  def perform(family_id, scheduled_at)
    Rails.logger.info("[RetiredBills] Ignored IdentifyRecurringTransactionsJob")
  end
end
