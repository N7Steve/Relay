# frozen_string_literal: true

class Investment::RoboadvisorPerformance
  RETURN_ACTIVITY_LABELS = [ nil, "Dividend", "Interest", "Fee", "Other" ].freeze

  attr_reader :account

  def initialize(account)
    @account = account
  end

  # Provider-native time-weighted return for a period. This is the preferred
  # percentage because deposits, withdrawals and rebalances do not distort it.
  def rate_for(date_range)
    native = provider_rate_for(date_range)
    return native unless native.nil?
    return if provider_history?

    profit_loss = balance_profit_loss(date_range)
    opening = opening_balance(date_range.begin)
    return if profit_loss.nil? || !opening&.positive?

    rate = profit_loss / opening
    rate if rate > -1
  end

  def provider_rate_for(date_range)
    return if local_value_updates?(date_range.end)
    points = return_index
    before = points.select { |date, _value| date < date_range.begin }.max_by(&:first)
    ending = points.select { |date, _value| date <= date_range.end }.max_by(&:first)
    return unless before && ending && ending.first >= date_range.begin
    return unless before.last.positive? && ending.last.positive?

    ending.last / before.last - 1
  end

  # Monetary P&L is decomposed day by day using the provider's time-weighted
  # index and previous portfolio value. This preserves the effect of capital
  # entering or leaving during the period without counting it as performance.
  def profit_loss_for(date_range)
    native = native_profit_loss_for(date_range)
    return native unless native.nil?

    balance_profit_loss(date_range)
  end

  def total_profit_loss
    native = parse_decimal(return_payload[:pl]) unless local_value_updates?
    return native unless native.nil?

    balance_profit_loss(nil)
  end

  def opening_balance(date)
    portfolio = portfolio_points.select { |row_date, _amount| row_date <= date }.max_by(&:first)
    return portfolio.last if portfolio && !local_value_updates?(date)

    balance = account.balances.where("date < ?", date).order(date: :desc).first
    balance&.balance
  end

  def provider_history?
    return_index.any? && !local_value_updates?
  end

  private

    def native_profit_loss_for(date_range)
      return if local_value_updates?(date_range.end)
      return if return_index.empty? || portfolio_points.empty?

      total = 0.to_d
      observations = 0
      return_index.each_cons(2) do |previous, current|
        current_date, current_index = current
        next unless date_range.cover?(current_date)

        previous_date, previous_index = previous
        next unless previous_index.positive? && current_index.positive?

        capital = portfolio_points.select { |date, _amount| date <= previous_date }.max_by(&:first)&.last
        next unless capital

        total += capital * (current_index / previous_index - 1)
        observations += 1
      end

      total if observations.positive?
    end

    def balance_profit_loss(date_range)
      rows = account.balances.order(:date)
      rows = rows.where(date: date_range) if date_range
      rows = rows.to_a
      transactions = performance_transactions(date_range)
      return if rows.empty? && transactions.empty?

      balance_only = !account.holdings.exists?
      first_balance_date = account.balances.minimum(:date)
      market_profit_loss = rows.sum do |balance|
        pnl = balance.net_market_flows
        if balance_only && balance.date != first_balance_date
          pnl += balance.cash_adjustments + balance.non_cash_adjustments
        end
        pnl
      end
      market_profit_loss + transactions.sum { |entry| transaction_profit_loss(entry) }
    end

    def performance_transactions(date_range)
      entries = account.entries.excluding_pending.excluding_split_parents
        .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
        .where(excluded: false)
        .where.not(transactions: { kind: Transaction::TRANSFER_KINDS })
        .where("transactions.kind = ? OR transactions.investment_activity_label IN (?) OR transactions.investment_activity_label IS NULL",
          "investment_value_adjustment", RETURN_ACTIVITY_LABELS.compact)
      entries = entries.where(date: date_range) if date_range
      entries.to_a
    end

    def transaction_profit_loss(entry)
      Money.new(-entry.amount, entry.currency)
        .exchange_to(account.currency, date: entry.date)
        .amount
    end

    def local_value_updates?(ending = Date.current)
      account.transactions.where(kind: "investment_value_adjustment")
        .where("transactions.extra ? 'investment_value'").joins(:entry)
        .where("entries.date <= ?", ending).exists?
    end

    def performance_payload
      @performance_payload ||= account.imported_performance.to_h.with_indifferent_access
    end

    def return_index
      @return_index ||= begin
        raw = return_payload[:index]
        if raw.is_a?(Hash)
          raw.filter_map do |date, value|
            parsed_date = parse_date(date)
            parsed_value = parse_decimal(value)
            [ parsed_date, parsed_value ] if parsed_date && parsed_value&.positive?
          end.sort_by(&:first)
        else
          []
        end
      end
    end

    def return_payload
      @return_payload ||= begin
        value = performance_payload[:return] || performance_payload.dig(:performance, :return) || {}
        value.to_h.with_indifferent_access
      end
    end

    def portfolio_points
      @portfolio_points ||= Array(performance_payload[:portfolios]).filter_map do |row|
        data = row.to_h.with_indifferent_access
        date = parse_date(data[:date])
        amount = parse_decimal(data[:total_amount])
        [ date, amount ] if date && amount
      end.sort_by(&:first)
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def parse_decimal(value)
      decimal = BigDecimal(value.to_s)
      decimal if decimal.finite?
    rescue ArgumentError
      nil
    end
end
