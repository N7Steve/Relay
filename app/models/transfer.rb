class Transfer < ApplicationRecord
  belongs_to :inflow_transaction, class_name: "Transaction", inverse_of: :transfer_as_inflow
  belongs_to :outflow_transaction, class_name: "Transaction", inverse_of: :transfer_as_outflow

  has_many :fee_transactions, class_name: "Transaction", foreign_key: :transfer_id,
           inverse_of: :fee_transfer, dependent: :destroy

  attr_accessor :source_fee_amount, :destination_fee_amount, :tag_ids
  attr_writer :name

  enum :status, { pending: "pending", confirmed: "confirmed" }

  attr_accessor :category_id

  validates :inflow_transaction_id, uniqueness: true
  validates :outflow_transaction_id, uniqueness: true

  validate :transfer_has_different_accounts
  validate :transfer_has_opposite_amounts
  validate :transfer_within_date_range
  validate :transfer_has_same_family
  validate :transfer_has_no_value_adjustment
  before_validation :assign_managed_operation
  after_save :normalize_managed_legs!
  after_destroy :clear_managed_operation

  class << self
    def outflow_kind_for(source, destination)
      if destination.cashflow_boundary? && !source.cashflow_boundary?
        "transfer_to_excluded"
      elsif source.cashflow_boundary? && !destination.cashflow_boundary?
        "transfer_from_excluded"
      elsif destination.loan?
        "loan_payment"
      elsif destination.credit_card? || destination.liability?
        "cc_payment"
      elsif (destination.investment? || destination.crypto?) && !(source.investment? || source.crypto?)
        "investment_contribution"
      else
        "funds_movement"
      end
    end

    def inflow_kind_for(source, destination)
      if destination.cashflow_boundary? && !source.cashflow_boundary?
        "transfer_to_excluded"
      elsif source.cashflow_boundary? && !destination.cashflow_boundary?
        "transfer_from_excluded"
      else
        "funds_movement"
      end
    end
  end

  def has_source_fee?
    derived_source_fee_amount > 0
  end

  def has_destination_fee?
    derived_destination_fee_amount > 0
  end

  def has_fees?
    has_source_fee? || has_destination_fee?
  end

  def total_fee
    totals = fees_by_currency
    return nil if totals.many?

    totals.values.first || 0.to_d
  end

  def fees_by_currency
    fee_transactions.joins(:entry).group("entries.currency").sum("entries.amount")
  end

  # Original denominations, grouped independently for each transfer leg.
  def fees_by_leg
    { source: from_account.id, destination: to_account.id }.transform_values do |account_id|
      fee_transactions.joins(:entry).where(entries: { account_id: account_id })
        .group("entries.currency").sum("entries.amount").map { |currency, amount| Money.new(amount, currency) }
    end
  end

  def source_total_money
    total_with_fees(outflow_transaction.entry.amount_money, :source)
  end

  def destination_total_money
    fees = fees_by_leg.fetch(:destination)
    amount = -inflow_transaction.entry.amount_money
    return nil unless fees.all? { |fee| fee.currency.iso_code == amount.currency.iso_code }

    fees.reduce(amount) { |total, fee| total - fee }
  end

  def total_with_fees(amount, leg)
    fees = fees_by_leg.fetch(leg)
    return nil unless fees.all? { |fee| fee.currency.iso_code == amount.currency.iso_code }

    fees.reduce(amount) { |total, fee| total + fee }
  end
  private :total_with_fees

  def derived_source_fee_amount
    fee_transactions.joins(:entry).where(entries: { account_id: from_account.id }).sum("entries.amount")
  end

  def derived_destination_fee_amount
    fee_transactions.joins(:entry).where(entries: { account_id: to_account.id }).sum("entries.amount")
  end

  def amount_abs
    inflow_transaction&.entry&.amount_money&.abs || Money.new(0, from_account&.currency || "USD")
  end

  def name
    return native_name if managed_operation
    return @name if @name.present?

    outflow_name = outflow_transaction&.entry&.name
    return outflow_name if outflow_name.present?

    acc = to_account
    if payment?
      acc ? "Payment to #{acc.name}" : "Payment"
    else
      acc ? "Transfer to #{acc.name}" : "Transfer"
    end
  end

  def payment?
    to_account&.liability?
  end

  def loan_payment?
    outflow_transaction&.kind == "loan_payment"
  end

  def liability_payment?
    outflow_transaction&.kind == "cc_payment"
  end

  def regular_transfer?
    outflow_transaction&.kind == "funds_movement"
  end

  def transfer_type
    return "loan_payment" if loan_payment?
    return "liability_payment" if liability_payment?
    "transfer"
  end

  def categorizable?
    managed_operation.nil?
  end

  def managed_operation
    Investment::NativeOperation.transfer_type(from_account, to_account) unless destroyed?
  end

  def native_name
    Investment::NativeOperation.transfer_name(from_account, to_account)
  end

  def normalize_managed_legs!
    assign_managed_operation
    [ outflow_transaction, inflow_transaction ].compact.each do |transaction|
      entry = transaction.entry
      next unless entry
      entry.entryable = transaction
      entry.save! if entry.changed? || transaction.changed?
    end
  end

  def reject!
    Transfer.transaction do
      RejectedTransfer.find_or_create_by!(inflow_transaction_id: inflow_transaction_id, outflow_transaction_id: outflow_transaction_id)
      destroy!
    end
  end

  def destroy!
    Transfer.transaction do
      [ inflow_transaction, outflow_transaction ].each do |transaction|
        next if transaction.nil?
        next unless Transaction.exists?(transaction.id)
        begin
          transaction.update!(kind: "standard")
          # The entry survives this destroy (only the Transfer join row and
          # fee transactions go away), but its idempotency_key must not: a
          # later retry of the original create request looks up that key,
          # finds no Transfer anymore, and would otherwise hit the unique
          # index on the stale entry and raise instead of creating a new
          # transfer (see Transfer::Creator#find_existing_transfer).
          transaction.entry.update!(idempotency_key: nil) if transaction.entry&.idempotency_key.present?
        rescue ActiveRecord::RecordNotFound
        rescue NoMethodError
          next
        end
      end
      super
    end
  end

  def confirm!
    update!(status: "confirmed")
  end

  # Reuse the same financial classification after linking or boundary changes.
  # Permissions, category assignment and recalculation remain with the caller.
  def reclassify_transactions!
    Transfer.transaction(requires_new: true) do
      outflow_transaction.update!(kind: self.class.outflow_kind_for(from_account, to_account))
      inflow_transaction.update!(kind: self.class.inflow_kind_for(from_account, to_account))
    end
  end

  def date
    inflow_transaction&.entry&.date
  end

  def sync_account_later
    inflow_transaction&.entry&.sync_account_later
    outflow_transaction&.entry&.sync_account_later
    fee_transactions.each { |t| t.entry&.sync_account_later }
  end

  def to_account
    inflow_transaction&.entry&.account
  end

  def from_account
    outflow_transaction&.entry&.account
  end

  private
    def assign_managed_operation
      operation = managed_operation
      [ outflow_transaction, inflow_transaction ].compact.each do |transaction|
        next unless transaction.entry
        if operation
          Investment::NativeOperation.assign(transaction.entry, operation, native_name)
        elsif transaction.extra&.key?("native_managed_operation")
          transaction.extra = transaction.extra.except("native_managed_operation")
        end
      end
    end

    def clear_managed_operation
      Transaction.where(id: [ inflow_transaction_id, outflow_transaction_id ])
        .update_all("extra = extra - 'native_managed_operation'")
    end

    def transfer_has_no_value_adjustment
      if [ inflow_transaction, outflow_transaction ].compact.any?(&:investment_value_adjustment?)
        errors.add(:base, :invalid)
      end
    end

    def transfer_has_different_accounts
      return unless inflow_transaction&.entry && outflow_transaction&.entry
      errors.add(:base, :different_accounts) if to_account == from_account
    end

    def transfer_has_same_family
      return unless inflow_transaction&.entry && outflow_transaction&.entry
      errors.add(:base, :same_family) unless to_account&.family == from_account&.family
    end

    def transfer_has_opposite_amounts
      return unless inflow_transaction&.entry && outflow_transaction&.entry

      inflow_entry = inflow_transaction.entry
      outflow_entry = outflow_transaction.entry

      inflow_amount_raw = inflow_entry.amount
      outflow_amount_raw = outflow_entry.amount

      errors.add(:base, :opposite_amounts) unless inflow_amount_raw.negative? && outflow_amount_raw.positive?

      if inflow_entry.currency == outflow_entry.currency
        errors.add(:base, :opposite_amounts) if inflow_amount_raw + outflow_amount_raw != 0
      end
    end

    def transfer_within_date_range
      return unless inflow_transaction&.entry && outflow_transaction&.entry

      date_diff = (inflow_transaction.entry.date - outflow_transaction.entry.date).abs
      max_days = status == "confirmed" ? 30 : 4
      errors.add(:base, :within_days, count: max_days) if date_diff > max_days
    end
end
