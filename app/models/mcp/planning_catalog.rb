# frozen_string_literal: true

class Mcp::PlanningCatalog
  def self.definitions
    c = Mcp::Catalog
    budget = { budget_id: c::ID }
    payment = { scheduled_payment_id: c::ID }
    goal = { goal_id: c::ID }
    nullable_id = { type: [ "string", "null" ] }
    nullable_date = { type: [ "string", "null" ], pattern: c::DATE[:pattern] }
    schedule_attrs = { title: c::STRING, amount: c::MONEY, currency: { type: "string", pattern: "^[A-Z]{3}$" },
      frequency: { type: "string", enum: ScheduledPayment.frequencies.keys }, start_date: c::DATE, end_date: nullable_date,
      account_id: c::ID, target_account_id: nullable_id, category_id: nullable_id, merchant_id: nullable_id,
      payment_type: { type: "string", enum: ScheduledPayment.payment_types.keys }, auto_confirm: c::BOOLEAN, amount_estimated: c::BOOLEAN, tag_ids: c::IDS }
    goal_attrs = { name: c::STRING, target_amount: c::MONEY, target_date: nullable_date, color: c::STRING, icon: { type: [ "string", "null" ] }, notes: c::STRING,
      kind: { type: "string", enum: Goal::KINDS }, target_mode: { type: "string", enum: Goal::TARGET_MODES }, target_months: { type: "integer", minimum: 1 },
      accounts: { type: "array", minItems: 1, maxItems: 100, items: { type: "object", additionalProperties: false, required: [ "account_id" ], properties: {
        account_id: c::ID, allocated_amount: { type: [ "string", "null" ], pattern: c::MONEY[:pattern] }
      } } } }
    tools = [
      c.definition("list_budgets", c::PAGE, read: true),
      c.definition("get_budget", budget, required: [ "budget_id" ], read: true),
      c.definition("list_budget_allocations", budget.merge(c::PAGE), required: [ "budget_id" ], read: true),
      c.definition("create_budget", { month: c::DATE, household: c::BOOLEAN }, required: [ "month" ]),
      c.definition("update_budget", budget.merge(budgeted_spending: c::MONEY, expected_income: c::MONEY), required: [ "budget_id" ]),
      c.definition("update_budget_allocation", budget.merge(budget_category_id: c::ID, amount: c::MONEY, rollover_enabled: c::BOOLEAN), required: %w[budget_id budget_category_id amount]),
      c.definition("move_budget_funds", budget.merge(from_id: c::ID, to_id: c::ID, amount: c::MONEY), required: %w[budget_id from_id to_id amount]),
      c.definition("copy_budget", budget.merge(source_budget_id: c::ID), required: [ "budget_id" ]),
      c.definition("recompute_budget_rollover", budget, required: [ "budget_id" ]),
      c.definition("delete_budget", budget, required: [ "budget_id" ], destructive: true),
      c.definition("list_scheduled_payments", c::PAGE, read: true),
      c.definition("get_scheduled_payment", payment, required: [ "scheduled_payment_id" ], read: true),
      c.definition("get_agenda", c::PAGE.merge(month: c::DATE), required: [ "month" ], read: true),
      c.definition("create_scheduled_payment", schedule_attrs.merge(from_transaction_id: c::ID), required: %w[title amount currency frequency start_date account_id payment_type]),
      c.definition("update_scheduled_payment", payment.merge(schedule_attrs), required: [ "scheduled_payment_id" ]),
      c.definition("set_scheduled_payment_status", payment.merge(status: { type: "string", enum: %w[active paused] }), required: %w[scheduled_payment_id status]),
      c.definition("delete_scheduled_payment", payment, required: [ "scheduled_payment_id" ], destructive: true),
      c.definition("confirm_scheduled_date", payment.merge(scheduled_date: c::DATE, confirm_date: c::DATE, amount: c::MONEY), required: %w[scheduled_payment_id scheduled_date]),
      c.definition("skip_scheduled_date", payment.merge(scheduled_date: c::DATE), required: %w[scheduled_payment_id scheduled_date]),
      c.definition("run_scheduled_payments", payment, required: [ "scheduled_payment_id" ]),
      c.definition("list_goals", c::PAGE, read: true),
      c.definition("get_goal", goal, required: [ "goal_id" ], read: true),
      c.definition("create_goal", goal_attrs, required: %w[name target_amount accounts]),
      c.definition("update_goal", goal.merge(goal_attrs), required: [ "goal_id" ]),
      c.definition("transition_goal", goal.merge(event: { type: "string", enum: %w[pause resume complete archive unarchive reopen] }), required: %w[goal_id event]),
      c.definition("delete_goal", goal, required: [ "goal_id" ], destructive: true),
      c.definition("record_goal_consumption", goal.merge(account_id: c::ID, transaction_id: c::ID, amount: c::MONEY), required: %w[goal_id account_id amount]),
      c.definition("list_goal_pledges", goal.merge(c::PAGE), required: [ "goal_id" ], read: true),
      c.definition("create_goal_pledge", goal.merge(account_id: c::ID, amount: c::MONEY), required: %w[goal_id account_id amount]),
      c.definition("reconcile_goal_pledge", goal.merge(pledge_id: c::ID, transaction_id: c::ID), required: %w[goal_id pledge_id transaction_id])
    ]
    %w[confirm reject retract restore revert_future purge_pending].each do |action|
      attrs = payment.merge(occurrence_id: c::ID)
      attrs = attrs.merge(confirm_date: c::DATE, amount: c::MONEY) if action == "confirm"
      attrs = attrs.merge(reason: c::STRING) if action == "reject"
      tools << c.definition("#{action}_scheduled_entry", attrs, required: %w[scheduled_payment_id occurrence_id], destructive: %w[retract purge_pending].include?(action))
    end
    %w[renew cancel expire].each do |action|
      tools << c.definition("#{action}_goal_pledge", goal.merge(pledge_id: c::ID), required: %w[goal_id pledge_id])
    end
    tools
  end
end
