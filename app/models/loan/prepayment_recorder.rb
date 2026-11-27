# Records an extra repayment: the contractual choice (Loan::Prepayment) and,
# when the borrower names the account it came from, the transfer that moved
# the money -- with the lender's fee charged on the paying side. Without a
# source account the money is expected to be on the loan account already
# (imported from the bank, or entered by hand) and is linked when found.
class Loan::PrepaymentRecorder
  attr_reader :loan, :source_account

  def initialize(loan, source_account: nil)
    @loan = loan
    @source_account = source_account
  end

  # Returns the prepayment, persisted or carrying its errors.
  def record(paid_on: nil, amount: nil, mode: nil, fee: 0, notes: nil)
    prepayment = loan.prepayments.build(paid_on: paid_on, amount: amount, mode: mode, fee: fee.presence || 0, notes: notes)
    return prepayment unless prepayment.valid?

    Loan::Prepayment.transaction do
      prepayment.entry = if source_account
        transfer_from_source(prepayment).inflow_transaction.entry
      else
        prepayment.matching_entry
      end
      prepayment.save!
    end

    loan.reload
    loan.sync_scheduled_payments!
    loan.account.sync_later
    prepayment
  end

  private
    def transfer_from_source(prepayment)
      Transfer::Creator.new(
        family: loan.account.family,
        source_account_id: source_account.id,
        destination_account_id: loan.account.id,
        date: prepayment.paid_on,
        amount: prepayment.amount,
        name: I18n.t("loans.prepayments.transfer_name", account: loan.account.name),
        source_fee_amount: prepayment.fee
      ).create
    end
end
