class TransferMatchesController < ApplicationController
  before_action :set_entry

  def new
    @accounts = Current.family.accounts.writable_by(Current.user).sidebar_visible.alphabetically.where.not(id: @entry.account_id)
    writable_ids = @accounts.pluck(:id)
    @transfer_match_candidates = @entry.transaction.transfer_match_candidates.select do |candidate|
      other_account = @entry.amount.positive? ? candidate.inflow_transaction.entry.account_id : candidate.outflow_transaction.entry.account_id
      writable_ids.include?(other_account)
    end
    @multiple_candidates = @transfer_match_candidates.many?
  end

  def create
    return unless require_account_permission!(@entry.account, redirect_path: transactions_path)

    target_account = resolve_target_account
    return unless require_account_permission!(target_account, redirect_path: transactions_path)

    @transfer = build_transfer
    Transfer.transaction do
      @transfer.save!

      # Keep investment category assignment separate from kind classification.
      source_account = @transfer.outflow_transaction.entry.account
      destination_account = @transfer.inflow_transaction.entry.account
      outflow_kind = Transfer.outflow_kind_for(source_account, destination_account)
      @transfer.reclassify_transactions!

      if outflow_kind == "investment_contribution"
        category = destination_account.family.investment_contributions_category
        if category.present? && @transfer.outflow_transaction.category_id.blank?
          @transfer.outflow_transaction.update!(category: category)
        end
      end
    end

    @transfer.sync_account_later

    redirect_back_or_to transactions_path, notice: t(".success")
  end

  private
    def set_entry
      @entry = Current.accessible_entries.find(params[:transaction_id])
    end

    def transfer_match_params
      params.require(:transfer_match).permit(:method, :matched_entry_id, :target_account_id)
    end

    def resolve_target_account
      if transfer_match_params[:method] == "new"
        accessible_accounts.find(transfer_match_params[:target_account_id])
      else
        Current.accessible_entries.find(transfer_match_params[:matched_entry_id]).account
      end
    end

    def build_transfer
      if transfer_match_params[:method] == "new"
        target_account = accessible_accounts.find(transfer_match_params[:target_account_id])

        missing_transaction = Transaction.new(
          entry: target_account.entries.build(
            amount: @entry.amount * -1,
            currency: @entry.currency,
            date: @entry.date,
            name: "Transfer to #{@entry.amount.negative? ? @entry.account.name : target_account.name}",
            user_modified: true,
          )
        )

        transfer = Transfer.find_or_initialize_by(
          inflow_transaction: @entry.amount.positive? ? missing_transaction : @entry.transaction,
          outflow_transaction: @entry.amount.positive? ? @entry.transaction : missing_transaction
        )
        transfer.status = "confirmed"
        transfer
      else
        target_transaction = Current.accessible_entries.find(transfer_match_params[:matched_entry_id])

        transfer = Transfer.find_or_initialize_by(
          inflow_transaction: @entry.amount.negative? ? @entry.transaction : target_transaction.transaction,
          outflow_transaction: @entry.amount.negative? ? target_transaction.transaction : @entry.transaction
        )
        transfer.status = "confirmed"
        transfer
      end
    end
end
