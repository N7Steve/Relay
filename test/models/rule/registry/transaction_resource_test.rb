require "test_helper"

class Rule::Registry::TransactionResourceTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
  end

  test "historical AI rules remain displayable but cannot mutate transactions" do
    rule = build_rule(action_type: "auto_categorize")

    keys = rule.registry.action_executors.map(&:key)

    assert_includes keys, "auto_categorize"
    assert_not_includes keys, "auto_detect_merchants"
    assert_instance_of Rule::ActionExecutor::AutoCategorize, rule.actions.first.executor
    assert_equal 0, rule.actions.first.executor.execute(@family.transactions)
  end

  test "existing auto categorization actions stay displayable when no provider is configured" do
    rule = build_rule(action_type: "auto_categorize")

    keys = rule.registry.action_executors.map(&:key)

    assert_includes keys, "auto_categorize"
    assert_instance_of Rule::ActionExecutor::AutoCategorize, rule.actions.first.executor
  end

  test "new auto categorization actions are hidden when no provider is configured" do
    rule = build_rule(action_type: "exclude_transaction")

    keys = rule.registry.action_executors.map(&:key)

    assert_not_includes keys, "auto_categorize"
  end

  private
    def build_rule(action_type:)
      @family.rules.create!(
        name: "Transaction registry test",
        resource_type: "transaction",
        effective_date: 1.day.ago.to_date,
        actions: [ Rule::Action.new(action_type: action_type) ]
      )
    end
end
