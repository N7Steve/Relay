# Typing an index value by hand, from the lender's notice or the official
# bulletin, when the automatic import is off or has not caught up. Index values
# are instance-wide -- every family's revisions read them -- so only a super
# admin can write them; a family admin is an admin of one family.
class Loans::ReferenceRatesController < ApplicationController
  include LoanRateTermsScoped

  before_action :require_admin!

  def new
    @reference_rate = ReferenceRate.new(index_key: params[:index_key].presence || "euribor_12m",
                                         month: Date.current.beginning_of_month.prev_month)
  end

  def create
    @reference_rate = ReferenceRate.find_or_initialize_by(
      index_key: reference_rate_params[:index_key],
      month: parsed_month
    )
    @reference_rate.assign_attributes(value: reference_rate_params[:value], source: "manual")

    if @reference_rate.save
      after_terms_change!
      redirect_to rates_tab_path, notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def require_admin!
      redirect_to rates_tab_path, alert: t("accounts.not_authorized") unless Current.user.super_admin?
    end

    def reference_rate_params
      params.require(:reference_rate).permit(:index_key, :month, :value)
    end

    # The form sends a month (YYYY-MM); the row stores its first day. An
    # unreadable value is left nil for the presence validation to report.
    def parsed_month
      Date.strptime(reference_rate_params[:month].to_s.first(7), "%Y-%m")
    rescue Date::Error
      nil
    end
end
