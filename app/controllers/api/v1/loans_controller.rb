# frozen_string_literal: true

# Read-only view of the loans the user can read: the debt, the instalment in
# force, how the rate is built and the amortization schedule. Every figure is
# read off the loan's own engine (schedule, rate reviewer, payoff projection),
# as the web loan page does, for one reference date per request so the parts
# of a response agree with each other.
class Api::V1::LoansController < Api::V1::BaseController
  before_action :ensure_read_scope

  def index
    @as_of = Date.current
    @accounts = loan_accounts.alphabetically.to_a

    render :index
  end

  def show
    raise ActiveRecord::RecordNotFound, "Loan not found" unless valid_uuid?(params[:id])

    @as_of = Date.current
    @account = loan_accounts.find(params[:id])

    render :show
  end

  private

    def ensure_read_scope
      authorize_scope!(:read)
    end

    # The same accounts GET /accounts lists, narrowed to loans.
    def loan_accounts
      current_resource_owner.family.accounts
                            .accessible_by(current_resource_owner)
                            .visible
                            .where(accountable_type: "Loan")
                            .includes(:accountable, account_providers: :provider)
                            .with_attached_logo.with_attached_custom_logo
    end
end
