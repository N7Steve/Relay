class Account::Recalculator
  def initialize(account)
    @account = account
  end

  def recalculate(window_start_date: nil)
    ExternalAccess.locally do
      @account.transaction do
        strategy = @account.reverse_balance_history? ? :reverse : :forward
        Balance::Materializer.new(@account, strategy: strategy, window_start_date: window_start_date).materialize_balances
        apply_imported_balance_history
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
    def apply_imported_balance_history
      Account::ImportedBalanceHistory.new(@account).sync! if @account.imported_balance_history.present?
    end
end
