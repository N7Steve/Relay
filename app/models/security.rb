class Security < ApplicationRecord
  # Raised by local recalculation when no stored, trade or holding price covers a date.
  MissingPriceError = Class.new(StandardError)

  # ISO 10383 MIC codes mapped to user-friendly exchange names
  # Source: https://www.iso20022.org/market-identifier-codes
  # Data stored in config/exchanges.yml
  EXCHANGES = YAML.safe_load_file(Rails.root.join("config", "exchanges.yml")).freeze

  # Legacy non-ISO values previously persisted as exchange_operating_mic
  # (e.g. raw EODHD exchange codes) mapped to their ISO MIC.
  MIC_ALIASES = {
    "WAR" => "XWAR"
  }.freeze

  KINDS = %w[standard cash].freeze

  # Exchange code stored on crypto pairs by the price provider retired in pruning phase 9A.
  CRYPTO_MIC = "BNCX".freeze
  CRYPTO_QUOTE_CURRENCIES = %w[USD EUR JPY BRL TRY].freeze

  # Builds the Brandfetch crypto URL for a base asset (e.g. "BTC"). Returns
  # nil when Brandfetch isn't configured.
  # The symbol goes into a URL path segment, and it comes from provider data —
  # an on-chain token can be called anything its deployer chose. A slash, a
  # question mark or a hash would not merely break the link: they would point
  # the path elsewhere on the CDN, or push the client id into a fragment where
  # Brandfetch never sees it. Guarded here rather than at each call site, since
  # six of them reach this method from four different providers.
  SAFE_CRYPTO_SYMBOL = /\A[A-Za-z0-9][A-Za-z0-9.\-]{0,31}\z/

  def self.brandfetch_crypto_url(base_asset)
    return nil if base_asset.blank?
    return nil unless base_asset.to_s.match?(SAFE_CRYPTO_SYMBOL)

    Setting.brand_fetch_icon_url(base_asset, namespace: "crypto")
  end

  # Classification taxonomy: the six-class / twelve-sub-class scheme other
  # portfolio trackers use, so an import maps onto it without a translation
  # table. The database enforces the same sets (chk_securities_asset_class,
  # chk_securities_asset_sub_class, chk_securities_classification_source);
  # adding a value means changing both, deliberately.
  #
  # Schema only for now: nothing writes these columns yet, so every security
  # is unclassified (NULL) until a later drop populates them.
  #
  # The migration repeats these lists rather than reading them from here, so
  # that it produces the same schema whenever it runs. Changing a list is
  # therefore a two-file edit, and "the model taxonomy and the database
  # constraint list the same values" fails if only one side moves.
  #
  # `sector` and `industry` have no constants and no validation on purpose:
  # they hold provider vocabulary, which no two providers agree on. An
  # `inclusion` rule there would reject a value a provider legitimately
  # returns.
  #
  # `region` is NOT the same case, and grouping it with those two would be
  # wrong. No provider supplies a region -- they supply a country, and the
  # region is derived from it against a list this application owns -- so its
  # vocabulary is closed and a model-level `inclusion` validation is the right
  # enforcement once something writes it. It is unconstrained today only
  # because nothing does. It is left unconstrained in the DATABASE for a
  # different reason: the list belongs in configuration, where widening it
  # should not need a migration. The migration header says the same.
  ASSET_CLASSES = %w[
    alternative_investment commodity equity fixed_income liquidity real_estate
  ].freeze

  ASSET_SUB_CLASSES = %w[
    bond cash collectible commodity cryptocurrency etf loan mutual_fund
    precious_metal private_equity real_estate stock
  ].freeze

  # Same shape as Holding's cost-basis provenance: who set the classification,
  # so a later writer knows whether it may replace it. `classification_locked`
  # is the user's veto over every source.
  CLASSIFICATION_SOURCES = %w[provider manual ai default].freeze

  before_validation :upcase_symbols
  before_save :generate_logo_url_from_brandfetch, if: :should_generate_logo?

  has_many :trades, dependent: :nullify, class_name: "Trade"
  has_many :prices, dependent: :destroy

  validates :ticker, presence: true
  validates :ticker, uniqueness: { scope: :exchange_operating_mic, case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }
  validates :asset_class, inclusion: { in: ASSET_CLASSES }, allow_nil: true
  validates :asset_sub_class, inclusion: { in: ASSET_SUB_CLASSES }, allow_nil: true
  validates :classification_source, inclusion: { in: CLASSIFICATION_SOURCES }, allow_nil: true

  scope :online, -> { where(offline: false) }
  scope :standard, -> { where(kind: "standard") }

  # Parses a "SYMBOL|EXCHANGE" ticker value. Older clients may append a provider segment, which is ignored.
  def self.parse_combobox_id(value)
    parts = value.to_s.split("|", 3)
    { ticker: parts[0].presence, exchange_operating_mic: parts[1].presence }
  end

  # Lazily finds or creates a synthetic cash security for an account.
  # Used as fallback when creating an interest Trade without a user-selected
  # security, and to represent non-primary-currency cash positions as holdings
  # (issue #1809). When a currency that differs from the account's primary
  # currency is given, a distinct per-currency security is created so balances
  # in different currencies don't collide.
  def self.cash_for(account, currency: nil)
    distinct = currency.present? && currency.to_s.upcase != account.currency.to_s.upcase
    ticker = (distinct ? "CASH-#{account.id}-#{currency}" : "CASH-#{account.id}").upcase
    find_or_create_by!(ticker: ticker, kind: "cash") do |s|
      s.name = distinct ? "Cash (#{currency.to_s.upcase})" : "Cash"
      s.offline = true
    end
  end

  def cash?
    kind == "cash"
  end

  def crypto?
    exchange_operating_mic == CRYPTO_MIC
  end

  # Base asset of a stored crypto pair (BTCUSD, BTC-EUR or CRYPTO:BTC -> BTC).
  def crypto_base_asset
    return nil unless crypto?

    symbol = ticker.to_s.upcase.delete_prefix("CRYPTO:")
    quote = CRYPTO_QUOTE_CURRENCIES.find { |currency| symbol.length > currency.length && symbol.end_with?(currency) }
    symbol = symbol.delete_suffix(quote).sub(/[-\/_ ]\z/, "") if quote
    symbol.presence
  end

  # Single source of truth for which logo URL the UI should render.
  # - Crypto keeps its dedicated Brandfetch-crypto shape.
  # - When a website domain is known, Brandfetch (consistent client_id + size)
  #   wins, falling back to any stored logo_url.
  # - With no domain, a stored provider logo (e.g. T-Invest's CDN for MOEX
  #   instruments) is authoritative and beats the ticker-only Brandfetch
  #   lettermark placeholder.
  def display_logo_url
    return nil unless ExternalAccess.enabled?(:logos)
    if crypto?
      self.class.brandfetch_crypto_url(crypto_base_asset).presence || logo_url.presence
    elsif website_url.present?
      brandfetch_icon_url.presence || logo_url.presence
    else
      logo_url.presence || brandfetch_icon_url.presence
    end
  end

  # Returns user-friendly exchange name for a MIC code
  def self.exchange_name_for(mic)
    return nil if mic.blank?
    EXCHANGES.dig(mic.upcase, "name") || mic.upcase
  end

  def self.canonical_exchange_operating_mic(mic)
    return nil if mic.blank?

    key = mic.to_s.upcase
    MIC_ALIASES.fetch(key, key)
  end

  # Values that should match the same venue for DB lookup (canonical + legacy aliases).
  def self.exchange_operating_mic_lookup_values(mic)
    return [] if mic.blank?

    canonical = canonical_exchange_operating_mic(mic)
    aliases = MIC_ALIASES.select { |_legacy, canon| canon == canonical }.keys
    ([ canonical ] + aliases).uniq
  end

  # Finds a security by ticker + MIC, treating legacy MIC aliases as the same
  # venue. When a legacy row is found, upgrades it to the canonical MIC unless
  # a canonical row already exists (in which case the canonical row wins).
  #
  # When +exchange_operating_mic+ is blank:
  # - match_blank_mic: true  → only rows with a blank MIC (find-or-initialize)
  # - match_blank_mic: false → do not filter by MIC (exact DB match by ticker)
  def self.find_by_ticker_and_exchange(ticker:, exchange_operating_mic: nil, country_code: nil, match_blank_mic: false)
    return nil if ticker.blank?

    scope = where("UPPER(ticker) = ?", ticker.to_s.upcase)

    if exchange_operating_mic.present?
      mics = exchange_operating_mic_lookup_values(exchange_operating_mic)
      scope = scope.where("UPPER(exchange_operating_mic) IN (?)", mics)
    elsif match_blank_mic
      scope = scope.where(exchange_operating_mic: [ nil, "" ])
    end

    scope = scope.where(country_code: country_code) if country_code.present?

    canonical = canonical_exchange_operating_mic(exchange_operating_mic)
    security = if canonical.present?
      scope.order(
        Arel.sql(
          sanitize_sql_array([
            "CASE WHEN UPPER(COALESCE(exchange_operating_mic, '')) = ? THEN 0 ELSE 1 END",
            canonical
          ])
        )
      ).first
    else
      scope.first
    end

    return nil unless security
    return security if canonical.blank?
    return security if security.exchange_operating_mic.to_s.upcase == canonical

    existing_canonical = find_by(ticker: security.ticker, exchange_operating_mic: canonical)
    return existing_canonical if existing_canonical

    security.update!(exchange_operating_mic: canonical)
    security
  end

  def self.find_or_initialize_by_ticker_and_exchange(ticker:, exchange_operating_mic: nil)
    existing = find_by_ticker_and_exchange(
      ticker: ticker,
      exchange_operating_mic: exchange_operating_mic,
      match_blank_mic: exchange_operating_mic.blank?
    )
    return existing if existing

    new(
      ticker: ticker,
      exchange_operating_mic: canonical_exchange_operating_mic(exchange_operating_mic)
    )
  end

  def exchange_name
    self.class.exchange_name_for(exchange_operating_mic)
  end

  def current_price
    @current_price ||= prices.find_by(date: Date.current)
    return nil if @current_price.nil?
    Money.new(@current_price.price, @current_price.currency)
  end

  def brandfetch_icon_url(width: nil, height: nil)
    identifier = extract_domain(website_url) if website_url.present?
    identifier ||= ticker

    Setting.brand_fetch_icon_url(identifier, width: width, height: height)
  end

  private

    def extract_domain(url)
      uri = URI.parse(url)
      host = uri.host || url
      host.sub(/\Awww\./, "")
    rescue URI::InvalidURIError
      nil
    end

    def upcase_symbols
      self.ticker = ticker.upcase
      self.exchange_operating_mic = self.class.canonical_exchange_operating_mic(exchange_operating_mic) if exchange_operating_mic.present?
    end

    def should_generate_logo?
      return false if cash?
      return false unless Setting.brand_fetch_client_id.present?

      return true if logo_url.blank?
      return false unless logo_url.include?("cdn.brandfetch.io")

      website_url_changed? || ticker_changed?
    end

    def generate_logo_url_from_brandfetch
      self.logo_url = if crypto?
        self.class.brandfetch_crypto_url(crypto_base_asset)
      else
        brandfetch_icon_url
      end
    end
end
