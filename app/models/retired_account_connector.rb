# Stable names used by historical snapshots, polymorphic links and queued jobs.
# These models contain persistence only and are never registered as adapters.
class RetiredAccountConnector
  PREFIXES = %w[Akahu Binance Brex Coinbase Coinspot Coinstats Financekit Fio Ibkr IndexaCapital Kraken Lunchflow Mercury Monobank OnchainWallet Plaid Questrade Redbark Simplefin Snaptrade Sophtron TradeRepublic Trading212 Up Wise].freeze

  # Provider records that do not follow the Item/Account naming pair.
  EXTRA_MODEL_NAMES = %w[FinancekitAccountLineage].freeze

  def self.model_names
    PREFIXES.flat_map { |prefix| [ "#{prefix}Item", "#{prefix}Account" ] } + EXTRA_MODEL_NAMES
  end

  def self.syncable_type?(name)
    PREFIXES.any? { |prefix| name == "#{prefix}Item" }
  end
end
