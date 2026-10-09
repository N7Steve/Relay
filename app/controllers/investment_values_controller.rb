class InvestmentValuesController < ApplicationController
  before_action :set_account, only: %i[new create]
  before_action :set_entry, only: %i[show update]

  def new
    return unless require_account_permission!(@account)
    @value_update = Investment::ValueUpdate.new(account: @account, amount: @account.balance)
  end

  def create
    return unless require_account_permission!(@account)
    @value_update = Investment::ValueUpdate.new(value_params.merge(account: @account))
    if @value_update.save
      redirect_to account_path(@account), notice: t("investment_values.saved"), status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @value_update = Investment::ValueUpdate.new(account: @account, entry: @entry,
      date: @entry.date, amount: @entry.transaction.investment_value_target)
  end

  def update
    return unless require_account_permission!(@account)
    raise ActiveRecord::RecordNotFound unless @entry.transaction.investment_value_target
    @value_update = Investment::ValueUpdate.new(value_params.merge(account: @account, entry: @entry))
    if @value_update.save
      redirect_to account_path(@account), notice: t("investment_values.saved"), status: :see_other
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def set_account
      @account = accessible_accounts.find(params[:account_id] || params.dig(:investment_value, :account_id))
      raise ActiveRecord::RecordNotFound unless @account.managed_portfolio?
    end

    def set_entry
      @entry = Current.accessible_entries.where(entryable_type: "Transaction")
        .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id").where(transactions: { kind: "investment_value_adjustment" }).find(params[:id])
      @account = @entry.account
    end

    def value_params
      params.require(:investment_value).permit(:amount, :date)
    end
end
