# Completes accounting for old rule-run jobs without modifying transactions.
class AutoCategorizeJob < ApplicationJob
  queue_as :medium_priority

  def perform(family, transaction_ids: [], rule_run_id: nil)
    RuleRun.find_by(id: rule_run_id)&.complete_job!(modified_count: 0) if rule_run_id.present?
  end
end
