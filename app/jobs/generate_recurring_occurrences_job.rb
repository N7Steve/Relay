# Compatibility sink for serialized jobs from before pruning phase 8.
class GenerateRecurringOccurrencesJob < ApplicationJob
  queue_as :scheduled

  def perform(family_id = nil)
    Rails.logger.info("[RetiredBills] Ignored GenerateRecurringOccurrencesJob")
  end
end
