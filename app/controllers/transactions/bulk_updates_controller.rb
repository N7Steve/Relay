class Transactions::BulkUpdatesController < ApplicationController
  def new
  end

  def create
    # Skip split parents from bulk update - update children instead
    financial = bulk_update_params.slice(:date, :name).values.any?(&:present?)
    accounts = financial ? Current.family.accounts.writable_by(Current.user) : Current.family.accounts.annotatable_by(Current.user)
    updated = Current.family
                     .entries
                     .where(account_id: accounts.select(:id))
                     .excluding_split_parents
                     .excluding_transfer_transactions
                     .where(id: bulk_update_params[:entry_ids])
                     .includes(:entryable)
                     .bulk_update!(bulk_update_params, update_tags: tags_provided?)

    redirect_back_or_to transactions_path, notice: "#{updated} transactions updated"
  end

  private
    def bulk_update_params
      params.require(:bulk_update)
            .permit(:date, :notes, :name, :category_id, :merchant_id, entry_ids: [], tag_ids: [])
    end

    # Check if tag_ids was explicitly provided in the request.
    # This distinguishes between "user wants to update tags" vs "user didn't touch tags field".
    def tags_provided?
      bulk_update = params[:bulk_update]
      bulk_update.respond_to?(:key?) && bulk_update.key?(:tag_ids)
    end
end
