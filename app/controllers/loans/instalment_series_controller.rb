# Hands the Agenda series that pays the instalment to the loan, or creates it.
# Once the loan owns it, the amount of every occurrence is the schedule's and
# the series can no longer be deleted or re-pointed from Agenda.
class Loans::InstalmentSeriesController < ApplicationController
  include LoanRateTermsScoped

  def new
    @candidates = @loan.instalment_series_candidates.includes(:account).to_a
    @source_accounts = source_accounts
  end

  def create
    if @loan.instalment_series
      redirect_to rates_tab_path, alert: t(".already_linked")
      return
    end

    series = if params[:scheduled_payment_id].present?
      @loan.instalment_series_candidates.find(params[:scheduled_payment_id])
    end
    source = source_accounts.find_by(id: params[:source_account_id]) if series.nil?

    if series.nil? && source.nil?
      redirect_to rates_tab_path, alert: t(".choose")
      return
    end

    @loan.adopt_instalment_series!(scheduled_payment: series, source_account: source, title: params[:title])
    redirect_to rates_tab_path, notice: t(".success")
  end

  private
    def source_accounts
      Current.family.accounts.writable_by(Current.user).where.not(id: @account.id)
        .where(classification: "asset", currency: @account.currency).visible.alphabetically
    end
end
