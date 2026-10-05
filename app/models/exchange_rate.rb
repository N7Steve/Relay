class ExchangeRate < ApplicationRecord
  # Maximum number of days to look back for a stored rate.
  NEAREST_RATE_LOOKBACK_DAYS = 5

  validates :from_currency, :to_currency, :date, :rate, presence: true
  validates :date, uniqueness: { scope: %i[from_currency to_currency] }

  class << self
    # Stored rates only: Relay has no exchange rate provider. Weekend and holiday
    # dates reuse the nearest stored rate from the previous few days.
    def find_rate(from:, to:, date: Date.current)
      find_by(from_currency: from, to_currency: to, date: date) ||
        where(from_currency: from, to_currency: to)
          .where(date: (date - NEAREST_RATE_LOOKBACK_DAYS)..date)
          .order(date: :desc)
          .first
    end

    # Batch-loads rates for multiple source currencies.
    # Missing rates raise when consumed, so unrelated currencies do not block a
    # report and a foreign amount can never silently be valued at parity.
    def rates_for(currencies, to:, date: Date.current)
      unique_currencies = currencies.uniq
      return {} if unique_currencies.empty?

      exact_rates = where(from_currency: unique_currencies, to_currency: to, date: date)
                      .index_by(&:from_currency)

      missing = unique_currencies - exact_rates.keys

      nearest_rates = if missing.any?
        where(from_currency: missing, to_currency: to)
          .where(date: (date - NEAREST_RATE_LOOKBACK_DAYS)..date)
          .order(date: :desc)
          .to_a
          .each_with_object({}) do |r, map|
            map[r.from_currency] ||= r  # keep most-recent (first due to ORDER BY date DESC)
          end
      else
        {}
      end

      result = Hash.new do |_, currency|
        next 1 if currency == to

        raise Money::ConversionError.new(from_currency: currency, to_currency: to, date: date)
      end
      unique_currencies.each_with_object(result) do |currency, rates|
        rate = exact_rates[currency] || nearest_rates[currency]
        if rate && rate.date != date
          Rails.logger.debug("FX rate #{currency}/#{to}: using #{rate.date} for #{date} (gap=#{(date - rate.date).to_i}d)")
        end
        rates[currency] = rate.rate if rate
      end
    end
  end
end
