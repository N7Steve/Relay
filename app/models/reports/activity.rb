# Reports show managed portfolio performance beside income and expenses. Market
# movements are neither: counting them as income would distort savings rates.
class Reports::Activity
  Totals = Data.define(:income, :expenses, :investment_return)

  def initialize(family, user:, accounts: nil)
    @family = family
    @user = user
    @accounts = accounts
    @investment_statement = InvestmentStatement.new(family, user: user, accounts: accounts)
    @income_statement = IncomeStatement.new(family, user: user, accounts: accounts)
    @totals = {}
    @investment_returns = {}
  end

  def totals(period:)
    @totals[[ period.start_date, period.end_date ]] ||= begin
      cash = @income_statement.totals(transactions_scope: cash_transactions.in_period(period), date_range: period.date_range)
      performance = investment_return(period: period)
      Totals.new(income: cash.income_money, expenses: cash.expense_money, investment_return: performance)
    end
  end

  def investment_return(period:, account_id: nil)
    returns = investment_returns(period: period)
    returns = returns.select { |id, _| id == account_id } if account_id.present?
    Money.new(returns.values.sum(&:amount), @family.currency)
  end

  # Each managed portfolio counted in the report with its return for the period.
  def investment_returns_by_account(period:)
    returns = investment_returns(period: period)
    managed_accounts.map { |account| [ account, returns.fetch(account.id) ] }
  end

  def cash_transactions
    @cash_transactions ||= begin
      scope = @family.transactions.visible.where.not(id: performance_transactions.select(:id))
      @accounts ? scope.where(entries: { account_id: @accounts.select(:id) }) : scope
    end
  end

  private
    def managed_accounts
      @managed_accounts ||= @investment_statement.roboadvisor_accounts.reject do |account|
        @family.tax_advantaged_account_ids.include?(account.id)
      end
    end

    def investment_returns(period:)
      @investment_returns[[ period.start_date, period.end_date ]] ||= managed_accounts.to_h do |account|
        [ account.id, @investment_statement.roboadvisor_account_period_return(account, period: period) ]
      end
    end

    # These distributions, fees and native adjustments already belong to the
    # portfolio's P&L. Keeping them as cash income/expenses would count them twice.
    def performance_transactions
      @family.transactions.joins(:entry)
        .where(entries: { account_id: managed_accounts.map(&:id) })
        .where.not(kind: Transaction::TRANSFER_KINDS)
        .where("transactions.kind = ? OR transactions.investment_activity_label IN (?) OR transactions.investment_activity_label IS NULL",
          "investment_value_adjustment", Investment::RoboadvisorPerformance::RETURN_ACTIVITY_LABELS.compact)
    end
end
