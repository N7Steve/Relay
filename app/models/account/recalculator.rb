class Account::Recalculator
  def initialize(account)
    @account = account
  end

  def recalculate(window_start_date: nil)
    ExternalAccess.locally do
      @account.transaction do
        strategy = @account.linked? ? :reverse : :forward
        Balance::Materializer.new(@account, strategy: strategy, window_start_date: window_start_date).materialize_balances
        apply_cached_provider_balances
      end
    end
  rescue Money::ConversionError, Security::MissingPriceError => error
    DebugLogEntry.capture(
      category: "balance_calculation", level: "warn", message: error.message,
      source: self.class.name, family: @account.family, account: @account,
      metadata: { preserved_previous_balances: true }
    )
    raise
  end

  private
    def apply_cached_provider_balances
      return unless @account.linked_to?("IbkrAccount")

      provider = @account.account_providers.find_by(provider_type: "IbkrAccount")&.provider
      IbkrAccount::HistoricalBalancesSync.new(provider).sync! if provider
    end
end
