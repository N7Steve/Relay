# Historical Bills persistence for backups, legacy imports and GlobalIDs.
# No detection, scheduling, matching or financial callbacks remain.
class RecurringTransaction < ApplicationRecord
  include Monetizable

  MAX_END_AFTER_COUNT = 600

  belongs_to :family
  belongs_to :account, optional: true
  belongs_to :destination_account, optional: true, class_name: "Account"
  belongs_to :merchant, optional: true
  belongs_to :category, optional: true
  belongs_to :replaced_by, optional: true, class_name: "RecurringTransaction"
  has_many :recurrence_rules, -> { order(:position) }, dependent: :destroy, autosave: true
  has_many :recurring_occurrences, dependent: :destroy
  has_many :recurring_match_rejections, dependent: :destroy
  has_many :recurring_price_changes, dependent: :destroy

  monetize :amount
  monetize :expected_amount_min, allow_nil: true
  monetize :expected_amount_max, allow_nil: true
  monetize :expected_amount_avg, allow_nil: true

  enum :status, { suggested: "suggested", active: "active", paused: "paused",
                  inactive: "inactive", ended: "ended" }
  enum :bill_type, { bill: "bill", subscription: "subscription", installment: "installment",
                     income: "income", transfer: "transfer", other: "other" }, prefix: :typed
  enum :amount_strategy, { fixed: "fixed", average: "average", last: "last" }, prefix: :amount
  enum :end_mode, { never: "never", on_date: "on_date", after_count: "after_count" }, prefix: :ends
  enum :weekend_adjust, { none: "none", skip: "skip", before: "before", after: "after" }, prefix: :weekend

  validates :amount, presence: true
  validates :currency, presence: true
  validates :expected_day_of_month, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 31 }
  validates :status, presence: true, inclusion: { in: statuses.keys }
  validates :occurrence_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  # 600 covers a 50-year monthly plan and a 10-year weekly one.
  validates :end_after_count,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_END_AFTER_COUNT },
            allow_nil: true
  validate :merchant_or_name_present
  validate :category_belongs_to_family
  validate :accounts_belong_to_family
  validate :amount_variance_consistency
  validate :transfer_endpoints_consistent
  validate :payment_url_is_http
  validate :anchor_required_for_intervals
  validate :end_mode_fields_consistent
  validate :bill_type_matches_shape

  normalizes :payment_url, with: ->(url) { normalize_payment_url(url) }

  before_validation :derive_transfer_bill_type

  EXPLICIT_SCHEME = %r{\A[a-zA-Z][a-zA-Z0-9+.\-]*:(?://|(?!\d))}

  def self.normalize_payment_url(url)
    stripped = url.to_s.strip
    return nil if stripped.blank?
    return stripped if stripped.match?(EXPLICIT_SCHEME)

    "https://#{stripped}"
  end

  def self.valid_payment_url?(url)
    return false if url.blank?

    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def transfer?
    destination_account_id.present?
  end

  private
    def merchant_or_name_present
      if merchant_id.blank? && name.blank?
        errors.add(:base, :merchant_or_name_required)
      end
    end

    def category_belongs_to_family
      return if category_id.blank? || family_id.blank?

      unless Category.where(id: category_id, family_id: family_id).exists?
        errors.add(:category_id, :invalid)
      end
    end

    def accounts_belong_to_family
      return if family_id.blank?

      { account: account, destination_account: destination_account }.each do |attribute, record|
        next if record.blank? || record.family_id == family_id

        errors.add(attribute, :wrong_family)
      end
    end

    def amount_variance_consistency
      if expected_amount_min.present? && expected_amount_max.present?
        if expected_amount_min > expected_amount_max
          errors.add(:expected_amount_min, :greater_than_max)
        end
      end
    end

    def payment_url_is_http
      return if payment_url.blank?

      errors.add(:payment_url, :invalid_scheme) unless self.class.valid_payment_url?(payment_url)
    end

    def derive_transfer_bill_type
      self.bill_type = "transfer" if transfer?
    end

    def bill_type_matches_shape
      if typed_transfer? && !transfer?
        errors.add(:bill_type, :transfer_shape_mismatch)
      end
    end

    def anchor_required_for_intervals
      return if anchor_date.present?
      return unless recurrence_rules.reject(&:marked_for_destruction?).any? { |rule| rule.interval.to_i > 1 }

      errors.add(:anchor_date, :required_for_intervals)
    end

    def end_mode_fields_consistent
      case end_mode
      when "on_date"
        errors.add(:end_on, :blank) if end_on.blank?
      when "after_count"
        if end_after_count.blank? || end_after_count.to_i < 1
          errors.add(:end_after_count, :blank)
        end
      end
    end

    def transfer_endpoints_consistent
      return if destination_account_id.blank?

      if account_id.blank?
        errors.add(:account, :required_for_transfer)
      elsif account.blank?
        # account_id references a row that was destroyed. Mirror the
        # destination_account.blank? branch so the source side surfaces a
        # normal validation error too. :required is the stock "must exist".
        errors.add(:account, :required)
      elsif destination_account.blank?
        # destination_account_id references a row that was destroyed (or never
        # existed). Surface as a normal validation error instead of letting
        # the FK fire on save.
        errors.add(:destination_account, :required)
      elsif account_id == destination_account_id
        errors.add(:destination_account, :same_as_source)
      elsif account.family_id != destination_account.family_id
        errors.add(:destination_account, :family_mismatch)
      end
    end
end
