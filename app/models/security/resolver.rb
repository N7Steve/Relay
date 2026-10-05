class Security::Resolver
  def initialize(symbol, exchange_operating_mic: nil, country_code: nil)
    @symbol = validate_symbol!(symbol)
    @exchange_operating_mic = Security.canonical_exchange_operating_mic(exchange_operating_mic)
    @country_code = country_code
  end

  # Returns the stored security for the ticker, or creates a local one.
  # Relay has no market data provider, so new securities are always offline.
  def resolve
    return nil if symbol.blank?

    exact_match_from_db || offline_security
  end

  private
    attr_reader :symbol, :exchange_operating_mic, :country_code

    def validate_symbol!(symbol)
      raise ArgumentError, "Symbol is required and cannot be blank" if symbol.blank?
      symbol.strip.upcase
    end

    def offline_security
      security = Security.find_or_initialize_by_ticker_and_exchange(
        ticker: symbol,
        exchange_operating_mic: exchange_operating_mic
      )

      security.assign_attributes(
        country_code: country_code,
        offline: true
      )

      security.save!

      security
    end

    def exact_match_from_db
      Security.find_by_ticker_and_exchange(
        ticker: symbol,
        exchange_operating_mic: exchange_operating_mic,
        country_code: country_code.presence
      )
    end
end
