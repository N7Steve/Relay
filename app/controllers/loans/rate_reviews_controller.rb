# Records the revisions that are due now, without waiting for the daily job.
# With `recalculate`, every calculated (not confirmed) revision is first
# dropped and recorded again from the current periods, bonuses and index
# values -- for terms entered in the wrong order, such as a period saved
# before its bonuses.
class Loans::RateReviewsController < ApplicationController
  include LoanRateTermsScoped

  def create
    if params[:recalculate].present?
      after_terms_change!(recalculate_from: @loan.origination_date)
      redirect_to rates_tab_path, notice: t(".recalculated")
    else
      after_terms_change!
      redirect_to rates_tab_path, notice: t(".success")
    end
  end
end
