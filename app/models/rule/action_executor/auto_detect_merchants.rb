# Reader for historical rules. No new rule can select this retired action.
class Rule::ActionExecutor::AutoDetectMerchants < Rule::ActionExecutor
  def label
    I18n.t("rules.retired_ai_action")
  end

  def execute(transaction_scope, value: nil, ignore_attribute_locks: false, rule_run: nil)
    0
  end
end
