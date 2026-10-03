# Shared helpers for holding calculators (ForwardCalculator / ReverseCalculator).
# Expects the including class to expose an `account` reader.
module Holding::TradeCalculatorHelpers
  private
    # Converts a trade's price into the account's currency, falling back to the
    # raw price when no exchange rate is available.
    def converted_trade_price(trade)
      Money.new(trade.price, trade.currency).exchange_to(account.currency).amount
    rescue Money::ConversionError
      raise if ExternalAccess.local_recalculation?
      trade.price
    end
end
