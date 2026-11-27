class Loans::RatePeriodsController < ApplicationController
  include LoanRateTermsScoped

  before_action :set_rate_period, only: %i[edit update destroy]

  def new
    @rate_period = @loan.rate_periods.build(
      starts_on: @loan.rate_periods.last ? nil : @loan.origination_date,
      rate_kind: "variable", reference_index: "euribor_12m", review_interval_months: 12
    )
  end

  def create
    @rate_period = @loan.rate_periods.build(rate_period_params)

    if @rate_period.save
      after_terms_change!(recalculate_from: @rate_period.starts_on)
      redirect_to rates_tab_path, notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    previous_start = @rate_period.starts_on
    if @rate_period.update(rate_period_params)
      after_terms_change!(recalculate_from: [ previous_start, @rate_period.starts_on ].min)
      redirect_to rates_tab_path, notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rate_period.destroy!
    after_terms_change!(recalculate_from: @rate_period.starts_on)
    redirect_to rates_tab_path, notice: t(".success")
  end

  private
    def set_rate_period
      @rate_period = @loan.rate_periods.find(params[:id])
    end

    def rate_period_params
      params.require(:loan_rate_period).permit(
        :starts_on, :rate_kind, :base_rate, :reference_index, :spread,
        :review_interval_months, :floor_rate, :lender_name, :applies_bonuses
      )
    end
end
