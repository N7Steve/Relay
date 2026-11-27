class Loan
  # The only door into the account of a contract-managed loan.
  #
  # A loan that posts its interest (`interest_tracking`) is a closed contract:
  # its account holds the opening principal, the interest the loan charges,
  # the instalments its own Agenda series pays and the prepayments recorded
  # from the loan. Nothing else may be written there, by any path -- a manual
  # transaction, a transfer form, a bank match, a rule, a bulk edit or the API
  # would each break the balance the interest is computed from, silently.
  #
  # The loan's own flows run inside `allow`; Entry::LoanContractGuard rejects
  # every other write. A case the contract does not cover yet is added here,
  # as code, rather than opened up as a manual edit.
  module ContractWrites
    STATE_KEY = :relay_loan_contract_write

    def self.allow
      previous = ActiveSupport::IsolatedExecutionState[STATE_KEY]
      ActiveSupport::IsolatedExecutionState[STATE_KEY] = true
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[STATE_KEY] = previous
    end

    def self.allowed?
      ActiveSupport::IsolatedExecutionState[STATE_KEY] == true
    end
  end
end
