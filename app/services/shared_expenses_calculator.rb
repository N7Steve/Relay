class SharedExpensesCalculator
  RENT_CATEGORY_NAME = "Rentas de Trabajo"

  def initialize(family, accounts: family.accounts)
    @family = family
    @accounts = accounts
  end

  # Calculates pending debt from all-time shared expenses
  def calculate_debt
    shared_transactions = reportable_transactions.where(shared_expense: true)
    family_currency = @family.currency

    total_expenses = 0
    total_income = 0

    shared_transactions.includes(:entry).find_each do |txn|
      converted = convert_amount(txn.entry, family_currency)
      if txn.entry.amount > 0
        total_expenses += converted
      else
        total_income += converted.abs
      end
    end

    half_expenses = total_expenses / 2
    pending_debt = [ half_expenses - total_income, 0 ].max

    {
      pending_debt: Money.new(pending_debt, family_currency),
      has_data: total_expenses > 0 || total_income > 0
    }
  end

  # Only the user's half of shared outflows belongs in adjusted spending.
  def calculate_adjusted_expenses(period)
    expenses = reportable_transactions.where(entries: { date: period.date_range }).where("entries.amount > 0")
    all_total = sum_expenses(expenses, @family.currency)
    shared_total = sum_expenses(expenses.where(shared_expense: true), @family.currency)
    Money.new(all_total - shared_total / 2, @family.currency)
  end

  # Calculates income only from the "Rentas de trabajo" category for a given period
  def calculate_rent_income(period)
    family_currency = @family.currency
    date_range = period.date_range

    category = @family.categories.where("LOWER(name) = LOWER(?)", RENT_CATEGORY_NAME).first
    return zero_money unless category

    # Include the category itself and all its subcategories
    category_ids = [ category.id ] + @family.categories.where(parent_id: category.id).pluck(:id)

    # Income transactions: amount < 0, in the given category
    income_scope = reportable_transactions
      .where(entries: { date: date_range })
      .where(category_id: category_ids)
      .where("entries.amount < 0")

    total = 0
    income_scope.includes(:entry).find_each do |txn|
      total += convert_amount(txn.entry, family_currency).abs
    end

    Money.new(total, family_currency)
  end

  private

    def zero_money
      Money.new(0, @family.currency)
    end

    def reportable_transactions
      Transaction
        .joins(entry: :account)
        .where(accounts: { family_id: @family.id, id: @accounts.select(:id) })
        .merge(Account.visible.included_in_reports)
        .where(entries: { entryable_type: "Transaction", excluded: false })
        .budget_reportable
    end

    def sum_expenses(scope, family_currency)
      total = 0
      scope.includes(:entry).find_each do |txn|
        total += convert_amount(txn.entry, family_currency)
      end
      total
    end

    def convert_amount(entry, target_currency)
      Money.new(entry.amount, entry.currency).exchange_to(target_currency, date: entry.date).amount
    end
end
