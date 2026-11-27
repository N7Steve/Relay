# Keeps the account of a contract-managed loan closed (see
# Loan::ContractWrites): no entry is created, changed or removed there except
# by the loan's own flows.
#
# Allowed outside them:
#   * the opening principal (an opening-anchor valuation), which the account
#     form and the opening-balance manager maintain;
#   * a note on an entry;
#   * removing an entry that is NOT part of the contract -- left over from
#     before the loan was managed -- so the account can be cleaned up;
#   * anything done while the whole account is being deleted.
module Entry::LoanContractGuard
  extend ActiveSupport::Concern

  # Columns a user edit may touch on a contract entry: the note, and the
  # bookkeeping an edit writes afterwards.
  FREE_COLUMNS = %w[notes updated_at locked_attributes user_modified import_protected].freeze

  included do
    validate :loan_contract_accepts_creation, on: :create
    validate :loan_contract_accepts_change, on: :update
    before_destroy :loan_contract_allows_removal, prepend: true
  end

  def on_contract_managed_loan?
    return @on_contract_managed_loan if defined?(@on_contract_managed_loan)

    @on_contract_managed_loan = account.present? && account.accountable_type == "Loan" &&
      account.accountable.is_a?(Loan) && account.accountable.contract_managed?
  end

  # Part of the loan's contract: its principal, its interest, an instalment
  # its Agenda series paid or a prepayment recorded from the loan.
  def loan_contract_entry?
    return false unless persisted?

    source == Loan::InterestLedger::SOURCE ||
      (valuation? && entryable.opening_anchor?) ||
      ScheduledPaymentEntry.where(entry_id: id).or(ScheduledPaymentEntry.where(transfer_entry_id: id)).exists? ||
      Loan::Prepayment.where(entry_id: id).exists?
  end

  # Whether a user may change or remove this entry through the ordinary
  # entry screens.
  def loan_contract_locked?
    on_contract_managed_loan? && loan_contract_entry?
  end

  private
    def loan_contract_open?
      Loan::ContractWrites.allowed? || !on_contract_managed_loan?
    end

    def opening_principal?
      valuation? && entryable&.opening_anchor?
    end

    def loan_contract_accepts_creation
      return if loan_contract_open? || opening_principal?

      errors.add(:base, :loan_contract_closed)
    end

    def loan_contract_accepts_change
      return if loan_contract_open? || opening_principal?
      return if (changes.keys - FREE_COLUMNS).empty?

      errors.add(:base, :loan_contract_closed)
    end

    def loan_contract_allows_removal
      return if loan_contract_open? || destroyed_by_association
      return unless loan_contract_entry?

      errors.add(:base, :loan_contract_closed)
      throw :abort
    end
end
