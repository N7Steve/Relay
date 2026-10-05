# Historical persistence only: provider coverage per currency pair, kept for backup
# compatibility after the exchange rate providers were retired in pruning phase 9A.
class ExchangeRatePair < ApplicationRecord
  validates :from_currency, :to_currency, presence: true
end
