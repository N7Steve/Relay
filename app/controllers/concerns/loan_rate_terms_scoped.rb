# Shared lookup for the controllers that edit a loan's structured rate terms.
# The route's :loan_id is the loan ACCOUNT's id, as for every accountable
# controller; editing needs write permission on that account.
module LoanRateTermsScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_loan_account
  end

  private
    def set_loan_account
      @account = Current.user.reachable_accounts.where(accountable_type: "Loan").find(params[:loan_id])
      require_account_permission!(@account)
      @loan = @account.loan
    end

    def rates_tab_path
      account_path(@account, tab: "rates")
    end

    # Terms changed: record any revision now due, recalculate the account so
    # the posted interest follows, and bring the Agenda instalment along.
    # `recalculate_from` is set when a period changed: its calculated
    # revisions from that date are recorded again from the corrected terms.
    def after_terms_change!(recalculate_from: nil)
      @loan.reload
      @loan.rate_reviewer.prune!(from: recalculate_from)
      @loan.rate_reviewer.record_due!
      @loan.sync_scheduled_payments!
      @account.sync_later
    end
end
