module Transaction::Transferable
  extend ActiveSupport::Concern

  included do
    has_one :transfer_as_inflow, class_name: "Transfer", foreign_key: "inflow_transaction_id", inverse_of: :inflow_transaction, dependent: :destroy
    has_one :transfer_as_outflow, class_name: "Transfer", foreign_key: "outflow_transaction_id", inverse_of: :outflow_transaction, dependent: :destroy

    # We keep track of rejected transfers to avoid auto-matching them again
    has_one :rejected_transfer_as_inflow, class_name: "RejectedTransfer", foreign_key: "inflow_transaction_id", dependent: :destroy
    has_one :rejected_transfer_as_outflow, class_name: "RejectedTransfer", foreign_key: "outflow_transaction_id", dependent: :destroy

    after_save :sync_transfer_category, if: :saved_change_to_category_id?
  end

  def paired_transfer
    transfer_as_inflow || transfer_as_outflow
  end

  # Compatibility for existing callers: this has always returned the paired
  # transfer. A fee's parent is exposed separately through fee_transfer.
  def transfer
    paired_transfer
  end

  def transfer_match_candidates(
    date_window: 30,
    exchange_rate_tolerance: Family::AutoTransferMatchable.manual_match_exchange_rate_tolerance
  )
    candidates_scope = if self.entry.amount.negative?
      family_matches_scope(date_window: date_window, exchange_rate_tolerance: exchange_rate_tolerance, inflow_transaction_id: self.id)
    else
      family_matches_scope(date_window: date_window, exchange_rate_tolerance: exchange_rate_tolerance, outflow_transaction_id: self.id)
    end

    ids = candidates_scope.flat_map { |match| [ match.inflow_transaction_id, match.outflow_transaction_id ] }.uniq
    transactions = Transaction.includes(entry: :account).where(id: ids).index_by(&:id)
    candidates_scope.map do |match|
      Transfer.new(
        inflow_transaction: transactions.fetch(match.inflow_transaction_id),
        outflow_transaction: transactions.fetch(match.outflow_transaction_id),
      )
    end
  end

  private
    def sync_transfer_category
      xfer = paired_transfer
      return unless xfer

      sibling = if xfer.inflow_transaction_id == id
        xfer.outflow_transaction
      else
        xfer.inflow_transaction
      end

      return unless sibling
      return if sibling.category_id == category_id

      sibling.update_column(:category_id, category_id)
    end

    def family_matches_scope(date_window:, **filters)
      self.entry.account.family.transfer_match_candidates(date_window: date_window, **filters)
    end
end
