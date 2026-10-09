# Both forecast consumers use the same accessible schedules and confirmed links.
# An explicit link takes precedence over the heuristic, including irregular rows
# and either leg of a scheduled transfer. Rejected/skipped links explain nothing.
class ScheduledPayment::HistoryExplanation
  def initialize(payments:)
    @payments = payments.index_by(&:id)
    @heuristics = payments.select { |payment| payment.payment_type.in?(%w[expense income]) }.group_by(&:account_id)
  end

  def explains?(entry)
    linked_entry_ids.include?(entry.id) || @heuristics.fetch(entry.account_id, []).any? do |payment|
      payment.explains_forecast_entry?(entry)
    end
  end

  private

    def linked_entry_ids
      @linked_entry_ids ||= begin
        links = ScheduledPaymentEntry.confirmed.where(scheduled_payment_id: @payments.keys)
          .pluck(:scheduled_payment_id, :entry_id, :transfer_entry_id)
        accounts_by_entry = Entry.where(id: links.flat_map { |_, entry_id, transfer_entry_id| [ entry_id, transfer_entry_id ] }.compact)
          .pluck(:id, :account_id).to_h
        links.each_with_object(Set.new) do |(payment_id, entry_id, transfer_entry_id), ids|
          payment = @payments.fetch(payment_id)
          # Scope each linked leg to its declared account; do not allow a malformed
          # historical link to suppress unrelated financial evidence.
          ids << entry_id if entry_id && accounts_by_entry[entry_id] == payment.account_id
          ids << transfer_entry_id if transfer_entry_id && payment.transfer? && accounts_by_entry[transfer_entry_id] == payment.target_account_id
        end
      end
    end
end
