class CreditCardsController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id,
    :available_credit,
    :minimum_payment,
    :apr,
    :annual_fee,
    :expiration_date
  )

  def update
    super
    # Only apply provider settings once the account update succeeded (redirect);
    # a failed update renders :edit and must not persist the flag.
    if response.redirect?
      update_enable_banking_settings
    end
  end

  private
    def update_enable_banking_settings
      eb_params = params.permit(account: { enable_banking: [ :treat_balance_as_available_credit ] })
        .dig(:account, :enable_banking)
      return if eb_params.blank?

      update_provider_setting(
        provider_type: "EnableBankingAccount",
        attribute: :treat_balance_as_available_credit,
        value: ActiveModel::Type::Boolean.new.cast(eb_params[:treat_balance_as_available_credit])
      ) do |provider_account|
        # Re-sync so the balance is reinterpreted right away instead of on the next scheduled sync
        provider_account.enable_banking_item.sync_later
      end
    end


    def update_provider_setting(provider_type:, attribute:, value:)
      provider_account = @account.provider_account_for(provider_type)
      return unless provider_account.present?

      provider_account.update!(attribute => value)
      yield provider_account if provider_account.saved_change_to_attribute?(attribute)
    end
end
