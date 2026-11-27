# A published monthly value of an interest-rate index, such as the 12-month
# Euribor that Spanish variable mortgages are revised against.
#
# Instance-wide like ExchangeRate: an index value is a public fact, not family
# data. Rows come from ReferenceRate::Importer or from a user typing the value a
# bank letter quoted.
class ReferenceRate < ApplicationRecord
  # Index keys Relay knows how to name and, where a source exists, import.
  INDEXES = {
    "euribor_12m" => { source: "ecb" }
  }.freeze

  # Official Spanish mortgage indices are published with three decimals; the
  # bank applies the published figure, not the unrounded monthly average.
  PUBLISHED_PRECISION = 3

  validates :index_key, inclusion: { in: INDEXES.keys }
  validates :month, :value, :source, presence: true
  validates :month, uniqueness: { scope: :index_key }
  validate :month_is_first_of_month

  scope :for_index, ->(key) { where(index_key: key) }

  def self.index_options
    INDEXES.keys.map { |key| [ I18n.t("reference_rates.indexes.#{key}"), key ] }
  end

  # The value a revision applies, rounded as the index is published.
  def published_value
    value.round(PUBLISHED_PRECISION)
  end

  # The most recent value for `index_key` whose month ended before `date`, or
  # nil. `not_after_month` caps the month considered, so a revision can ask for
  # "the month before mine" and not pick up a value published later.
  def self.latest_before(index_key, date, not_after_month: nil)
    cap = date.beginning_of_month.prev_month
    cap = [ cap, not_after_month ].min if not_after_month
    for_index(index_key).where(month: ..cap).order(month: :desc).first
  end

  # Stores observations, replacing values for months already present. Returns
  # the number of rows written.
  def self.store!(index_key:, observations:, source:)
    now = Time.current
    rows = observations.map do |month, value|
      { index_key: index_key, month: month.beginning_of_month, value: value, source: source, created_at: now, updated_at: now }
    end
    return 0 if rows.empty?

    upsert_all(rows, unique_by: %i[index_key month], update_only: %i[value source])
    rows.size
  end

  private
    def month_is_first_of_month
      errors.add(:month, :invalid) if month.present? && month.day != 1
    end
end
