# frozen_string_literal: true

module Api::PlanningOperations
  def list_budgets(args)
    paginate(visible_budgets.order(start_date: :desc, id: :asc), args) { |record| budget_json(record) }
  end

  def get_budget(args)
    record = planning_budget(args.fetch("budget_id"))
    Budget::RolloverCalculator.new(family: family, user: record.user).recompute!
    budget_json(record.reload)
  end

  def list_budget_allocations(args)
    record = planning_budget(args.fetch("budget_id"))
    Budget::RolloverCalculator.new(family: family, user: record.user).recompute!
    paginate(record.budget_categories.reorder(:id), args) do |allocation|
      { id: allocation.id, category_id: allocation.category_id, name: allocation.name, currency: allocation.currency,
        allocated: allocation.budgeted_spending.to_d.to_s("F"), actual: record.budget_category_actual_spending(allocation).to_d.to_s("F"),
        rolled_over: allocation.rolled_over_amount.to_d.to_s("F"), rollover_enabled: allocation.rollover_enabled }
    end
  end

  def create_budget(args)
    owner = args["household"] || !family.personal_budgets? ? nil : user
    Budget::RolloverCalculator.new(family: family, user: owner).with_chain_lock do
      record = Budget.find_or_bootstrap(family, start_date: date(args.fetch("month")), user: user, household: args.fetch("household", false))
      invalid!("Budget month or household budget is unavailable") unless record
      budget_json(record)
    end
  end

  def update_budget(args)
    with_planning_budget(args) do |record|
      record.update!(args.slice("budgeted_spending", "expected_income").transform_values { |value| decimal(value) })
    end
  end

  def update_budget_allocation(args)
    with_planning_budget(args) do |record|
      allocation = record.budget_categories.find(args.fetch("budget_category_id"))
      if args.key?("rollover_enabled")
        allocation.update!(rollover_enabled: args["rollover_enabled"])
        allocation.propagate_rollover_choice_forward!
      end
      allocation.update_budgeted_spending!(decimal(args.fetch("amount")))
    end
  end

  def move_budget_funds(args)
    with_planning_budget(args) do |record|
      BudgetCategory.move_allocation!(from: record.budget_categories.find(args.fetch("from_id")), to: record.budget_categories.find(args.fetch("to_id")), amount: decimal(args.fetch("amount")))
    end
  end

  def copy_budget(args)
    with_planning_budget(args) do |record|
      invalid!("Target budget is already initialized") if record.initialized?
      source = args["source_budget_id"] ? planning_budget(args["source_budget_id"]) : record.most_recent_initialized_budget
      invalid!("No earlier initialized budget in this chain") unless source && source.family_id == record.family_id && source.user_id == record.user_id && source.start_date < record.start_date
      record.copy_from!(source)
    end
  end

  def recompute_budget_rollover(args)
    with_planning_budget(args) { |_record| }
  end

  def delete_budget(args)
    record = planning_budget(args.fetch("budget_id"), write: true)
    calculator = Budget::RolloverCalculator.new(family: family, user: record.user)
    calculator.with_chain_lock { record.destroy!; calculator.recompute! }
    { deleted: true }
  end

  def list_scheduled_payments(args)
    paginate(family.scheduled_payments.accessible_by(user).order(:title, :id), args) { |record| schedule_json(record) }
  end

  def get_scheduled_payment(args)
    schedule_json(planning_payment(args.fetch("scheduled_payment_id")))
  end

  def get_agenda(args)
    month = date(args.fetch("month"))
    invalid!("month must be its first day") unless month.day == 1
    agenda = ScheduledPayment::Agenda.new(family: family, user: user, month: month.iso8601)
    rows = agenda.month_occurrences
    page, limit = args.fetch("page", 1), args.fetch("per_page", 25)
    { month: month.iso8601, remaining_expenses: financial_json(agenda.remaining_expenses),
      recurring_monthly_expenses: financial_json(agenda.recurring_monthly_expenses), active_count: agenda.active_count, pending_count: agenda.pending_count,
      data: rows.slice((page - 1) * limit, limit).to_a.map { |row| { scheduled_payment_id: row.scheduled_payment.id, scheduled_date: row.scheduled_date.iso8601,
        occurrence_id: row.entry_id, status: row.status, amount: row.amount.to_d.to_s("F"), currency: row.currency } },
      pagination: { page: page, per_page: limit, total_count: rows.length, next_page: page * limit < rows.length ? page + 1 : nil } }
  end

  def create_scheduled_payment(args)
    attrs = schedule_attributes(args)
    record = family.scheduled_payments.new(attrs)
    record.next_run_date ||= record.start_date
    record.save!
    if args["from_transaction_id"]
      source = transaction_entry(args["from_transaction_id"], :write)
      invalid!("Historical source belongs to a different account") unless source.account_id == record.account_id
      record.link_matching_entries!(user, source_entry_id: source.id)
    end
    schedule_json(record)
  end

  def update_scheduled_payment(args)
    record = planning_payment(args.fetch("scheduled_payment_id"), write: true)
    record.with_lock { record.update!(schedule_attributes(args)); record.sync_confirmed_entries! }
    schedule_json(record)
  end

  def set_scheduled_payment_status(args)
    record = planning_payment(args.fetch("scheduled_payment_id"), write: true)
    record.with_lock do
      invalid!("Completed schedules cannot be reactivated") if record.completed?
      record.update!(status: args.fetch("status"))
    end
    schedule_json(record)
  end

  def delete_scheduled_payment(args)
    record = planning_payment(args.fetch("scheduled_payment_id"), write: true)
    record.with_lock { record.destroy! }
    { deleted: true }
  end

  def confirm_scheduled_date(args)
    record = planning_payment(args.fetch("scheduled_payment_id"), write: true)
    occurrence_json(record.confirm_on!(date(args.fetch("scheduled_date")), **confirmation_overrides(args)))
  rescue ArgumentError => error
    raise Api::Input::Invalid, error.message
  end

  def skip_scheduled_date(args)
    record = planning_payment(args.fetch("scheduled_payment_id"), write: true)
    occurrence_json(record.skip_on!(date(args.fetch("scheduled_date"))))
  rescue ArgumentError => error
    raise Api::Input::Invalid, error.message
  end

  def run_scheduled_payments(args)
    record = planning_payment(args.fetch("scheduled_payment_id"), write: true)
    count = 0
    while record.generate_pending_entry!(through: Date.current)
      count += 1
      invalid!("More than 100 occurrences are due; narrow the schedule start date") if count > 100
    end
    { generated: count, scheduled_payment: schedule_json(record.reload) }
  end

  %w[confirm reject retract restore revert_future purge_pending].each do |event|
    define_method("#{event}_scheduled_entry") do |args|
      payment = planning_payment(args.fetch("scheduled_payment_id"), write: true)
      record = payment.scheduled_payment_entries.find(args.fetch("occurrence_id"))
      case event
      when "confirm" then record.confirm!(**confirmation_overrides(args))
      when "reject" then record.reject!(args["reason"])
      else record.public_send("#{event}!")
      end
      record.destroyed? ? { removed: true, scheduled_date: record.scheduled_date.iso8601 } : occurrence_json(record.reload)
    end
  end

  def list_goals(args)
    paginate(planning_goals.order(:name, :id), args) { |record| goal_json(record) }
  end

  def get_goal(args)
    goal_json(planning_goal(args.fetch("goal_id")))
  end

  def create_goal(args)
    links = goal_links(args.fetch("accounts"))
    record = family.goals.new(goal_attributes(args).merge(currency: links.first[:account].currency))
    links.each { |link| record.goal_accounts.build(link) }
    record.save!
    goal_json(record)
  end

  def update_goal(args)
    record = planning_goal(args.fetch("goal_id"), write: true)
    record.with_lock do
      record.assign_attributes(goal_attributes(args))
      if args["accounts"]
        links = goal_links(args["accounts"])
        record.goal_accounts.where.not(account_id: links.map { |link| link[:account].id }).destroy_all
        record.goal_accounts.reload
        links.each do |link|
          existing = record.goal_accounts.find { |item| item.account_id == link[:account].id }
          if existing
            existing.allocated_amount = link[:allocated_amount] if link.key?(:allocated_amount)
          else
            record.goal_accounts.build(link)
          end
        end
      end
      record.save!
    end
    goal_json(record.reload)
  end

  def transition_goal(args)
    record = planning_goal(args.fetch("goal_id"), write: true)
    event = args.fetch("event")
    record.with_lock do
      invalid!("Goal transition is unavailable") unless record.aasm.may_fire_event?(event.to_sym) && record.public_send("#{event}!")
    end
    goal_json(record)
  end

  def delete_goal(args)
    record = planning_goal(args.fetch("goal_id"), write: true)
    record.destroy!
    { deleted: true }
  end

  def record_goal_consumption(args)
    record = planning_goal(args.fetch("goal_id"), write: true)
    selected_account = account(args.fetch("account_id"), :write)
    transaction = nil
    if args["transaction_id"]
      candidate = Goal::WithdrawalDetector.new(record, accounts: [ selected_account ]).unattributed_outflows(limit: 50).find_by!(entryable_id: args["transaction_id"])
      transaction = candidate.transaction
    end
    record.consume!(decimal(args.fetch("amount")), account: selected_account, transaction: transaction)
    goal_json(record)
  end

  def list_goal_pledges(args)
    record = planning_goal(args.fetch("goal_id"))
    paginate(record.goal_pledges.order(created_at: :desc, id: :asc), args) { |pledge| pledge_json(pledge) }
  end

  def create_goal_pledge(args)
    record = planning_goal(args.fetch("goal_id"), write: true)
    selected = record.linked_accounts.find(args.fetch("account_id"))
    access.require_account!(selected, :write)
    pledge = record.goal_pledges.create!(account: selected, amount: decimal(args.fetch("amount")), currency: record.currency, kind: selected.default_pledge_kind)
    pledge_json(pledge)
  end

  %w[renew cancel expire].each do |event|
    define_method("#{event}_goal_pledge") do |args|
      pledge = planning_goal(args.fetch("goal_id"), write: true).goal_pledges.find(args.fetch("pledge_id"))
      pledge.with_lock do
        invalid!("Pledge has not expired") if event == "expire" && pledge.expires_at > Time.current
        pledge.public_send(event == "renew" ? "extend!" : "#{event}!")
      end
      pledge_json(pledge)
    end
  end

  def reconcile_goal_pledge(args)
    pledge = planning_goal(args.fetch("goal_id"), write: true).goal_pledges.find(args.fetch("pledge_id"))
    entry = transaction_entry(args.fetch("transaction_id"), :write)
    invalid!("A pledge can only match an eligible inflow inside its match window") unless pledge.kind_transfer? && pledge.expires_at >= Time.current && pledge.matches?(entry) && !entry.excluded?
    pledge.resolve_with!(entry.transaction)
    pledge_json(pledge)
  end

  private
    def require_planning_preview!
      raise Api::Access::Forbidden, "Preview access is required for goals" unless user.preview_features_enabled?
    end

    def authorize_planning_arguments!(name, args)
      require_planning_preview! if name.include?("goal")
      write = !Mcp::Catalog.fetch(name)[:annotations][:readOnlyHint]
      planning_budget(args["budget_id"], write: write) if args["budget_id"]
      planning_goal(args["goal_id"], write: write) if args["goal_id"]
      planning_payment(args["scheduled_payment_id"], write: write) if args["scheduled_payment_id"]
    end

    def visible_budgets
      shared = BudgetShare.where(viewer_id: user.id).select(:owner_id)
      family.budgets.where(user_id: nil).or(family.budgets.where(user_id: user.id)).or(family.budgets.where(user_id: shared))
    end

    def planning_budget(id, write: false)
      record = visible_budgets.find(id)
      raise Api::Access::Forbidden, "Budget is shared for reading only" if write && !record.editable_by?(user)
      record.current_user = user
      record
    end

    def with_planning_budget(args)
      record = planning_budget(args.fetch("budget_id"), write: true)
      calculator = Budget::RolloverCalculator.new(family: family, user: record.user)
      calculator.with_chain_lock do
        yield record
        calculator.recompute!
        budget_json(record.reload)
      end
    end

    def budget_json(record)
      record.current_user = user
      { id: record.id, owner_id: record.user_id, currency: record.currency, start_date: record.start_date.iso8601, end_date: record.end_date.iso8601,
        editable: record.editable_by?(user), budgeted_spending: record.budgeted_spending&.to_d&.to_s("F"), expected_income: record.expected_income&.to_d&.to_s("F"),
        actual_spending: record.actual_spending.to_d.to_s("F"), actual_income: record.actual_income.to_d.to_s("F"),
        allocated_spending: record.allocated_spending.to_d.to_s("F"), available_to_allocate: record.available_to_allocate.to_d.to_s("F"),
        available_to_spend: record.available_to_spend.to_d.to_s("F"),
        available_cash: record.available_cash.to_d.to_s("F"), earmarked_for_goals: record.earmarked_for_goals.to_d.to_s("F"),
        free_cash: record.free_cash.to_d.to_s("F"), total_rolled_over: record.total_rolled_over.to_d.to_s("F") }
    end

    def planning_payment(id, write: false)
      record = family.scheduled_payments.accessible_by(user).find(id)
      if write
        record.ensure_writable_by!(user)
        access.require_account!(record.account, :write)
        access.require_account!(record.target_account, :write) if record.target_account
      end
      record
    end

    def schedule_attributes(args)
      attrs = args.slice("title", "amount", "currency", "frequency", "start_date", "end_date", "account_id", "target_account_id", "category_id", "merchant_id", "payment_type", "auto_confirm", "amount_estimated", "tag_ids")
      attrs["amount"] = decimal(attrs["amount"]) if attrs["amount"]
      %w[start_date end_date].each { |key| attrs[key] = date(attrs[key]) if attrs[key] }
      account(attrs["account_id"], :write) if attrs["account_id"]
      account(attrs["target_account_id"], :write) if attrs["target_account_id"]
      attrs
    end

    def confirmation_overrides(args)
      amount = decimal(args["amount"]) if args["amount"]
      invalid!("Confirmation amount must be non-negative") if amount&.negative?
      { date_override: args["confirm_date"] ? date(args["confirm_date"]) : nil, amount_override: amount }
    end

    def schedule_json(record)
      financial_json(record.attributes.slice("id", "title", "account_id", "target_account_id", "category_id", "merchant_id", "frequency", "frequency_day", "payment_type", "start_date", "end_date", "next_run_date", "amount", "currency", "status", "auto_confirm", "amount_estimated")).merge("tag_ids" => record.tag_ids)
    end

    def occurrence_json(record)
      record.as_json(only: %w[id scheduled_payment_id scheduled_date status entry_id transfer_entry_id rejection_reason])
    end

    def planning_goals
      hidden = family.accounts.where.not(id: access.accounts.select(:id)).select(:id)
      family.goals.where.not(id: GoalAccount.where(account_id: hidden).select(:goal_id))
        .where.not(id: GoalPledge.where(account_id: hidden).select(:goal_id))
    end

    def planning_goal(id, write: false)
      record = planning_goals.find(id)
      record.linked_accounts.each { |selected| access.require_account!(selected, :write) } if write
      if write
        family.accounts.where(id: record.goal_pledges.select(:account_id)).each { |selected| access.require_account!(selected, :write) }
      end
      record
    end

    def goal_links(rows)
      invalid!("Goal accounts must be unique") unless rows.map { |row| row["account_id"] }.uniq.length == rows.length
      rows.map do |row|
        selected = account(row.fetch("account_id"), :write)
        invalid!("Account cannot fund a goal") unless Goal::FUNDABLE_ACCOUNT_TYPES.include?(selected.accountable_type) && Account::VISIBLE_STATUSES.include?(selected.status)
        link = { account: selected }
        link[:allocated_amount] = row["allocated_amount"] ? decimal(row["allocated_amount"]) : nil if row.key?("allocated_amount")
        link
      end
    end

    def goal_attributes(args)
      attrs = args.slice("name", "target_amount", "target_date", "color", "icon", "notes", "kind", "target_mode", "target_months")
      attrs["target_amount"] = decimal(attrs["target_amount"]) if attrs["target_amount"]
      attrs["target_date"] = date(attrs["target_date"]) if attrs["target_date"]
      attrs
    end

    def goal_json(record)
      { id: record.id, name: record.name, currency: record.currency, kind: record.kind, state: record.state, status: record.display_status,
        target_amount: record.target_amount.to_d.to_s("F"), target_date: record.target_date&.iso8601,
        balance: record.current_balance.to_d.to_s("F"), consumed_amount: record.consumed_amount.to_d.to_s("F"), progress_percent: record.progress_percent,
        projection: financial_json(record.projection_payload), accounts: record.goal_accounts.map { |link| { account_id: link.account_id, allocated_amount: link.allocated_amount&.to_d&.to_s("F") } } }
    end

    def pledge_json(record)
      financial_json(record.attributes.slice("id", "goal_id", "account_id", "amount", "currency", "kind", "status", "expires_at", "matched_transaction_id"))
    end
end
