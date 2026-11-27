# A write that reached the account of a contract-managed loan from an ordinary
# screen fails in the model (Entry::LoanContractGuard). Whatever screen it came
# from, the user is sent back with what happened instead of an error page.
# Any other invalid record is re-raised untouched.
module LoanContractProtection
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed, with: :handle_loan_contract_closed
  end

  private
    def handle_loan_contract_closed(error)
      record = error.record
      raise error unless record.respond_to?(:errors) && record.errors.added?(:base, :loan_contract_closed)

      redirect_back_or_to root_path, alert: t("loans.contract.closed"), status: :see_other
    end
end
