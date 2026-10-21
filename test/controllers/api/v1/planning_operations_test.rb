# frozen_string_literal: true

require "test_helper"

class Api::V1::PlanningOperationsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => true))
    @key = ApiKey.create!(user: @user, name: "Planning", scopes: %w[read_write], source: "web", display_key: "planning_#{SecureRandom.hex(12)}")
    @account = accounts(:depository)
  end

  test "budget bootstrap allocation movement rollover and replay use one chain" do
    invoke("create_budget", month: Date.current.iso8601, idempotency_key: "budget")
    assert_response :success, response.body
    id = response.parsed_body.fetch("id")
    invoke("update_budget", budget_id: id, budgeted_spending: "1000", expected_income: "2000", idempotency_key: "init-budget")
    assert_response :success, response.body
    invoke("list_budget_allocations", budget_id: id, per_page: 100)
    assert_response :success, response.body
    allocation = Budget.find(id).budget_categories.find { |item| item.category.parent_id.nil? }
    invoke("update_budget_allocation", budget_id: id, budget_category_id: allocation.id, amount: "200", rollover_enabled: true, idempotency_key: "allocation")
    assert_response :success, response.body
    invoke("update_budget_allocation", budget_id: id, budget_category_id: allocation.id, amount: "200", rollover_enabled: true, idempotency_key: "allocation")
    assert_response :success
    assert_equal 200.to_d, allocation.reload.budgeted_spending
    invoke("recompute_budget_rollover", budget_id: id, idempotency_key: "rollover")
    assert_response :success
    invoke("list_budgets", per_page: 1)
    assert_response :success
    invoke("get_budget", budget_id: id)
    assert_response :success
  end

  test "read only budget share grants totals but never allocation writes or another chain" do
    owner = users(:family_member)
    budget = @user.family.budgets.create!(user: owner, start_date: 2.months.ago.to_date.beginning_of_month, end_date: 2.months.ago.to_date.end_of_month, currency: "USD")
    invoke("get_budget", budget_id: budget.id)
    assert_response :not_found
    BudgetShare.create!(owner: owner, viewer: @user, permission: "read_only")
    invoke("get_budget", budget_id: budget.id)
    assert_response :success, response.body
    invoke("update_budget", budget_id: budget.id, expected_income: "900", idempotency_key: "denied-budget")
    assert_response :forbidden
  end

  test "budget copies stay in owner chain and moves preserve total allocation" do
    source = budgets(:one)
    source.sync_budget_categories
    source.budget_categories.each { |row| row.update!(budgeted_spending: 0) }
    roots = source.budget_categories.select { |row| row.category.parent_id.nil? }.take(2)
    roots.first.update!(budgeted_spending: 200)
    invoke("move_budget_funds", budget_id: source.id, from_id: roots.first.id, to_id: roots.last.id, amount: "50", idempotency_key: "move")
    assert_response :success, response.body
    assert_equal 150.to_d, roots.first.reload.budgeted_spending
    assert_equal 50.to_d, roots.last.reload.budgeted_spending
    invoke("create_budget", month: (Date.current >> 1).iso8601, household: true, idempotency_key: "next-month")
    assert_response :success
    target_id = response.parsed_body.fetch("id")
    invoke("copy_budget", budget_id: target_id, source_budget_id: source.id, idempotency_key: "copy")
    assert_response :success, response.body
    assert_equal source.budgeted_spending, Budget.find(target_id).budgeted_spending
    invoke("delete_budget", budget_id: target_id, idempotency_key: "delete-budget")
    assert_response :success
    assert Budget.exists?(source.id)
  end

  test "pledge matching uses native date amount direction and single claim policy" do
    goal = goals(:vacation_italy)
    selected = accounts(:connected)
    pledge = goal.goal_pledges.create!(account: selected, amount: "77", currency: "USD", kind: "transfer")
    entry = selected.entries.create!(name: "Pledged deposit", amount: "-77", currency: "USD", date: Date.current, entryable: Transaction.new)
    args = { goal_id: goal.id, pledge_id: pledge.id, transaction_id: entry.entryable_id, idempotency_key: "reconcile" }
    invoke("reconcile_goal_pledge", args)
    assert_response :success, response.body
    invoke("reconcile_goal_pledge", args)
    assert_response :success
    assert_equal "matched", pledge.reload.status
    assert_equal pledge.id, entry.transaction.reload.extra.dig("goal", "pledge_id")
    expired = goal.goal_pledges.create!(account: @account, amount: "88", currency: "USD", kind: "manual_save", expires_at: 1.day.ago)
    invoke("expire_goal_pledge", goal_id: goal.id, pledge_id: expired.id, idempotency_key: "expire")
    assert_response :success
    assert_equal "expired", expired.reload.status
  end

  test "Agenda create confirm reject restore retract skip and deletion preserve native effects" do
    args = schedule_args.merge(idempotency_key: "schedule")
    invoke("create_scheduled_payment", args)
    assert_response :success, response.body
    id = response.parsed_body.fetch("id")
    invoke("create_scheduled_payment", args)
    assert_response :success
    assert_equal id, response.parsed_body.fetch("id")
    confirm = { scheduled_payment_id: id, scheduled_date: Date.current.iso8601, idempotency_key: "confirm" }
    assert_difference "Entry.count", 1 do
      invoke("confirm_scheduled_date", confirm)
      assert_response :success, response.body
      @occurrence_id = response.parsed_body.fetch("id")
      invoke("confirm_scheduled_date", confirm)
      assert_response :success
    end
    assert_difference "Entry.count", -1 do
      invoke("retract_scheduled_entry", scheduled_payment_id: id, occurrence_id: @occurrence_id, idempotency_key: "retract")
      assert_response :success, response.body
    end
    invoke("restore_scheduled_entry", scheduled_payment_id: id, occurrence_id: @occurrence_id, idempotency_key: "restore")
    assert_response :success
    assert_equal "confirmed", response.parsed_body.fetch("status")
    invoke("get_agenda", month: Date.current.beginning_of_month.iso8601)
    assert_response :success
    invoke("update_scheduled_payment", scheduled_payment_id: id, title: "Renamed schedule", idempotency_key: "update-schedule")
    assert_response :success, response.body
    invoke("skip_scheduled_date", scheduled_payment_id: id, scheduled_date: 1.month.from_now.to_date.iso8601, idempotency_key: "skip")
    assert_response :success, response.body
    invoke("set_scheduled_payment_status", scheduled_payment_id: id, status: "paused", idempotency_key: "pause-schedule")
    assert_response :success
    invoke("get_scheduled_payment", scheduled_payment_id: id)
    assert_response :success
    invoke("list_scheduled_payments", {})
    assert_response :success
    invoke("delete_scheduled_payment", scheduled_payment_id: id, idempotency_key: "delete-schedule")
    assert_response :success, response.body
  end

  test "Agenda pending occurrences reject skip restore future and bounded generation" do
    payment = @user.family.scheduled_payments.create!(schedule_args.except(:idempotency_key).merge(next_run_date: Date.current))
    invoke("run_scheduled_payments", scheduled_payment_id: payment.id, idempotency_key: "run")
    assert_response :success, response.body
    occurrence = payment.scheduled_payment_entries.first
    invoke("reject_scheduled_entry", scheduled_payment_id: payment.id, occurrence_id: occurrence.id, reason: "Not paid", idempotency_key: "reject")
    assert_response :success
    assert_equal "rejected", occurrence.reload.status
    invoke("confirm_scheduled_entry", scheduled_payment_id: payment.id, occurrence_id: occurrence.id, amount: "45", idempotency_key: "confirm-rejected")
    assert_response :success
    assert_equal "confirmed", occurrence.reload.status
    future = payment.scheduled_payment_entries.create!(scheduled_date: Date.current + 2.months, status: "pending")
    invoke("revert_future_scheduled_entry", scheduled_payment_id: payment.id, occurrence_id: future.id, idempotency_key: "revert-future")
    assert_response :success
    refute ScheduledPaymentEntry.exists?(future.id)
    other = payment.scheduled_payment_entries.create!(scheduled_date: Date.current + 3.months, status: "pending")
    invoke("purge_pending_scheduled_entry", scheduled_payment_id: payment.id, occurrence_id: other.id, idempotency_key: "purge-pending")
    assert_response :success
  end

  test "schedules enforce permissions for both current and historical accounts" do
    other = accounts(:credit_card)
    other.update!(owner: users(:family_member))
    AccountShare.where(account: other, user: @user).delete_all
    invoke("create_scheduled_payment", schedule_args.merge(payment_type: "transfer", target_account_id: other.id, idempotency_key: "denied-transfer"))
    assert_response :not_found
    invoke("create_scheduled_payment", schedule_args.merge(start_date: "2026-02-30", idempotency_key: "bad-date"))
    assert_response :unprocessable_entity
    invoke("create_scheduled_payment", schedule_args.merge(idempotency_key: "valid-date"))
    assert_response :success
    id = response.parsed_body.fetch("id")
    invoke("confirm_scheduled_date", scheduled_payment_id: id, scheduled_date: (Date.current - 1).iso8601, idempotency_key: "outside-schedule")
    assert_response :unprocessable_entity
  end

  test "Goals gate all operations and prevent private linked account disclosure" do
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => false))
    invoke("list_goals", {})
    assert_response :forbidden
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => true))
    private_account = accounts(:connected)
    private_account.update!(owner: users(:family_member))
    AccountShare.where(account: private_account, user: @user).delete_all
    goal = goals(:vacation_italy)
    goal.goal_accounts.find_or_create_by!(account: private_account) { |link| link.allocated_amount = 20 }
    invoke("get_goal", goal_id: goal.id)
    assert_response :not_found
  end

  test "goal creation update consumption transitions pledges expiry and deletion" do
    args = { name: "API goal", target_amount: "1000", accounts: [ { account_id: @account.id, allocated_amount: "1000" } ], idempotency_key: "goal" }
    invoke("create_goal", args)
    assert_response :success, response.body
    id = response.parsed_body.fetch("id")
    invoke("create_goal", args)
    assert_response :success
    assert_equal id, response.parsed_body.fetch("id")
    invoke("update_goal", goal_id: id, name: "Edited goal", idempotency_key: "edit-goal")
    assert_response :success
    invoke("record_goal_consumption", goal_id: id, account_id: @account.id, amount: "100", idempotency_key: "consume")
    assert_response :success, response.body
    assert_equal "100.0", response.parsed_body.fetch("consumed_amount")
    %w[pause resume complete reopen archive unarchive].each do |event|
      invoke("transition_goal", goal_id: id, event: event, idempotency_key: event)
      assert_response :success, response.body
    end
    # The native model forbids two open pledges on one account/goal.
    invoke("create_goal_pledge", goal_id: id, account_id: @account.id, amount: "30", idempotency_key: "pledge")
    assert_response :success, response.body
    pledge_id = response.parsed_body.fetch("id")
    assert_equal "manual_save", response.parsed_body.fetch("kind")
    invoke("renew_goal_pledge", goal_id: id, pledge_id: pledge_id, idempotency_key: "renew")
    assert_response :success
    invoke("expire_goal_pledge", goal_id: id, pledge_id: pledge_id, idempotency_key: "early-expire")
    assert_response :unprocessable_entity
    invoke("cancel_goal_pledge", goal_id: id, pledge_id: pledge_id, idempotency_key: "cancel")
    assert_response :success
    invoke("list_goal_pledges", goal_id: id)
    assert_response :success
    invoke("get_goal", goal_id: id)
    assert_response :success
    invoke("list_goals", per_page: 1)
    assert_response :success
    invoke("delete_goal", goal_id: id, idempotency_key: "delete-goal")
    assert_response :success
    assert Account.exists?(@account.id)
  end

  private
    def schedule_args
      { title: "API rent", amount: "50", currency: "USD", frequency: "monthly", start_date: Date.current.iso8601,
        account_id: @account.id, payment_type: "expense", auto_confirm: false }
    end

    def invoke(name, args)
      post "/api/v1/actions/#{name}", params: { arguments: args }, headers: { "X-Api-Key" => @key.display_key }, as: :json
    end
end
