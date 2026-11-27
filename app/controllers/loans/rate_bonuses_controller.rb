class Loans::RateBonusesController < ApplicationController
  include LoanRateTermsScoped

  before_action :set_rate_bonus, only: %i[edit update destroy]

  def new
    @rate_bonus = @loan.rate_bonuses.build(active: true, kind: "other")
  end

  def create
    @rate_bonus = @loan.rate_bonuses.build(rate_bonus_params)

    if @rate_bonus.save
      after_terms_change!
      redirect_to rates_tab_path, notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @rate_bonus.update(rate_bonus_params)
      after_terms_change!
      redirect_to rates_tab_path, notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rate_bonus.destroy!
    after_terms_change!
    redirect_to rates_tab_path, notice: t(".success")
  end

  private
    def set_rate_bonus
      @rate_bonus = @loan.rate_bonuses.find(params[:id])
    end

    def rate_bonus_params
      params.require(:loan_rate_bonus).permit(:name, :kind, :points, :active, :annual_cost)
    end
end
