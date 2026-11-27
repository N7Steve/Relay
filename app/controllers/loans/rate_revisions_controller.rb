# A recorded revision is edited only to bring it in line with the lender's
# notice; saving it marks it confirmed. Deleting one lets it be recorded again
# from the current terms.
class Loans::RateRevisionsController < ApplicationController
  include LoanRateTermsScoped

  before_action :set_rate_revision

  def edit
  end

  def update
    if @rate_revision.update(rate_revision_params.merge(status: "confirmed"))
      @loan.reload
      @loan.sync_scheduled_payments!
      @account.sync_later
      redirect_to rates_tab_path, notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rate_revision.destroy!
    after_terms_change!
    redirect_to rates_tab_path, notice: t(".success")
  end

  private
    def set_rate_revision
      @rate_revision = @loan.rate_revisions.find(params[:id])
    end

    def rate_revision_params
      params.require(:loan_rate_revision).permit(:rate, :index_value)
    end
end
