# Records the revisions that are due now, without waiting for the daily job.
class Loans::RateReviewsController < ApplicationController
  include LoanRateTermsScoped

  def create
    after_terms_change!
    redirect_to rates_tab_path, notice: t(".success")
  end
end
