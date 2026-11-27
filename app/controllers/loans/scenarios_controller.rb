# What-if comparisons for a loan, read-only and stateless: the form submits
# its fields as query parameters and the frame re-renders with the result.
class Loans::ScenariosController < ApplicationController
  before_action :set_loan_account

  def show
    @scenario = Loan::Scenario.new(loan: @loan, **scenario_params.to_h.symbolize_keys)
    @scenario.validate if @scenario.changes_anything?
  end

  private
    # Reading a loan's scenarios needs only access to it, not write permission.
    def set_loan_account
      @account = Current.user.reachable_accounts.where(accountable_type: "Loan").find(params[:loan_id])
      @loan = @account.loan
    end

    def scenario_params
      return ActionController::Parameters.new.permit unless params.key?(:scenario)

      params.require(:scenario).permit(
        :index_shift, :change_kind, :change_on, :change_rate, :change_spread, :change_cost, :keep_bonuses,
        :prepayment_amount, :prepayment_on, :prepayment_mode, :prepayment_fee
      ).compact_blank
    end
end
