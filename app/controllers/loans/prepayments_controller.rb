class Loans::PrepaymentsController < ApplicationController
  include LoanRateTermsScoped

  def new
    next_payment = @loan.payment_dates.find { |date| date >= Date.current }
    @prepayment = @loan.prepayments.build(paid_on: next_payment || Date.current, mode: "reduce_term", fee: 0)
    @source_accounts = source_accounts
  end

  def create
    source = source_accounts.find_by(id: params.dig(:loan_prepayment, :source_account_id).presence)
    @prepayment = Loan::PrepaymentRecorder.new(@loan, source_account: source).record(**prepayment_params.to_h.symbolize_keys)

    if @prepayment.persisted?
      redirect_to rates_tab_path, notice: t(".success")
    else
      @source_accounts = source_accounts
      render :new, status: :unprocessable_entity
    end
  end

  # Removes the contractual choice; on a contract-managed loan, its transfer
  # too (Loan::PrepaymentRecorder#remove).
  def destroy
    Loan::PrepaymentRecorder.new(@loan).remove(@loan.prepayments.find(params[:id]))
    after_terms_change!
    redirect_to rates_tab_path, notice: t(".success")
  end

  private
    def prepayment_params
      params.require(:loan_prepayment).permit(:paid_on, :amount, :mode, :fee, :notes)
    end

    # Accounts the user can move money out of, other than the loan itself.
    def source_accounts
      Current.family.accounts.writable_by(Current.user).where.not(id: @account.id)
        .where(classification: "asset", currency: @account.currency).visible.alphabetically
    end
end
