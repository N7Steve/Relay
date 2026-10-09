# A managed portfolio update is one native adjustment, optionally anchored to an
# absolute value. Historical adjustments have no target: their original deltas
# remain authoritative. New targets recalculate their deltas after backfills.
class Investment::ValueUpdate
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :amount, :decimal
  attribute :date, :date, default: -> { Date.current }
  attr_accessor :account, :entry

  def currency = account.currency

  def amount=(value)
    @raw_amount = value
    super
  end

  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :date, presence: true, comparison: { less_than_or_equal_to: -> { Date.current }, greater_than: -> { Entry.min_supported_date } }
  validate :managed_balance_tracking
  validate :finite_amount

  def save
    return false unless valid?

    account.with_lock do
      Account::Recalculator.new(account).recalculate
      if account.has_opening_anchor? && date <= account.opening_anchor_date
        errors.add(:date, I18n.t("investment_values.errors.before_opening"))
        return false
      end

      existing = account.entries.transactions.joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
        .where(date: date, transactions: { kind: "investment_value_adjustment" })
        .where("transactions.extra ? 'investment_value'").first
      if entry && existing && existing.id != entry.id
        errors.add(:date, I18n.t("investment_values.errors.duplicate_date"))
        return false
      end
      self.entry ||= existing || account.entries.build(entryable: Transaction.new(kind: "investment_value_adjustment"))
      metadata = entry.entryable.extra.to_h.merge("investment_value" => {
        "target" => amount.to_s("F"), "opening_value" => opening_value.to_s("F")
      })
      entry.assign_attributes(date: date, currency: account.currency, amount: entry.amount || 0,
        name: self.class.name_for(date), idempotency_key: "managed-value:#{date.iso8601}",
        entryable_attributes: { id: entry.entryable.id, extra: metadata })
      entry.save!
      Account::Recalculator.new(account).recalculate
      entry.reload
      entry.lock_saved_attributes!
      entry.mark_user_modified!
    end
    true
  rescue ActiveRecord::RecordInvalid => error
    errors.add(:base, error.record.errors.full_messages.to_sentence)
    false
  rescue Money::ConversionError, Security::MissingPriceError => error
    errors.add(:base, error.message)
    false
  end

  def self.name_for(date)
    I18n.t("investment_values.name", date: I18n.l(date, format: "%d/%m/%Y"))
  end

  def self.refresh_adjustments!(account)
    return unless account.managed_portfolio?

    updates = account.transactions.excluding_pending.where(kind: "investment_value_adjustment")
      .where("transactions.extra ? 'investment_value'").includes(:entry).to_a
    return if updates.empty?

    first = updates.min_by { |transaction| [ transaction.entry.date, transaction.entry.created_at, transaction.entry.id ] }
    value = BigDecimal(first.extra.fetch("investment_value").fetch("opening_value"))
    latest_date = updates.map { |transaction| transaction.entry.date }.max
    entries = account.entries.excluding_pending.excluding_split_parents.includes(:entryable).chronological.to_a
    observations = Account::ImportedBalanceHistory.new(account).closing_values_before(first.entry.date)
    entries_by_date = entries.group_by(&:date)
    (entries_by_date.keys | observations.keys).sort.each do |date|
      day_entries = entries_by_date.fetch(date, [])
      targets, other = day_entries.partition { |row| row.transaction? && row.transaction.investment_value_target.present? }
      movements, valuations = other.partition { |row| !row.valuation? }
      movements.each do |row|
        value -= row.amount_money.exchange_to(account.currency, date: date, custom_rate: row.entryable.try(:exchange_rate)).amount
      end
      valuations.each do |row|
        next if targets.any? || (row.valuation.current_anchor? && date <= latest_date)
        value = row.amount_money.exchange_to(account.currency, date: date, custom_rate: row.entryable.try(:exchange_rate)).amount
      end
      value = observations.fetch(date, value)
      targets.each do |row|
        target = row.transaction.investment_value_target
        row.update_columns(amount: value - target, updated_at: Time.current) if row.amount != value - target
        value = target
      end
    end

    if account.reverse_balance_history? && account.current_anchor_date <= latest_date
      result = account.set_current_balance(value, date: [ latest_date, entries.last&.date ].compact.max, schedule_sync: false)
      raise ActiveRecord::RecordInvalid.new(account) unless result.success?
    end
  end

  private
    def finite_amount
      number = BigDecimal(@raw_amount.to_s, exception: false)
      errors.add(:amount, :not_a_number) unless number&.finite?
    end

    def opening_value
      first = account.transactions.excluding_pending.where(kind: "investment_value_adjustment")
        .where("transactions.extra ? 'investment_value'").joins(:entry).order("entries.date", "entries.created_at").first
      return BigDecimal(first.extra.fetch("investment_value").fetch("opening_value")) if first
      return account.opening_anchor_balance if account.has_opening_anchor?

      account.balances.order(:date).first&.start_balance || 0.to_d
    end

    def managed_balance_tracking
      unless account&.managed_portfolio? && !account.holdings.exists? && !account.trades.exists?
        errors.add(:base, I18n.t("investment_values.errors.balance_tracking"))
      end
    end
end
