class LoansController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id, :subtype, :rate_type, :interest_rate, :term_months, :initial_balance, :start_date,
    :down_payment, :insurance_rate, :insurance_rate_type, :interest_accrual, :interest_tracking,
    { rate_changes: [ :effective_date, :rate ] }
  )
end
