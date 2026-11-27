# A stretch of a loan's life governed by one way of setting its rate: a fixed
# rate, or a reference index plus a spread. Periods follow one another; a
# period lasts until the next one starts. Switching to a fixed rate, or moving
# the loan to another lender, is a new period -- the earlier ones, and the
# revisions they produced, stay as they were.
#
# `review_interval_months` is how often the rate is set again within the
# period: the index revision of a variable period, and the bonus check of a
# fixed one (bonuses discount a fixed rate as well).
class Loan::RatePeriod < ApplicationRecord
  self.table_name = "loan_rate_periods"

  KINDS = %w[fixed variable].freeze

  belongs_to :loan

  validates :starts_on, presence: true, uniqueness: { scope: :loan_id }
  validates :rate_kind, inclusion: { in: KINDS }
  validates :base_rate, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: Loan::MAX_INTEREST_RATE }, if: :fixed?
  validates :reference_index, inclusion: { in: ReferenceRate::INDEXES.keys }, if: :variable?
  validates :spread, presence: true, numericality: { greater_than: -Loan::MAX_INTEREST_RATE, less_than_or_equal_to: Loan::MAX_INTEREST_RATE }, if: :variable?
  validates :review_interval_months, numericality: { only_integer: true, in: 1..120 }
  validates :floor_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: Loan::MAX_INTEREST_RATE }

  before_validation :clear_unused_terms

  scope :chronological, -> { order(:starts_on) }

  def fixed? = rate_kind == "fixed"
  def variable? = rate_kind == "variable"

  # The dates within [starts_on, ends_before) on which this period sets the
  # rate: its start, then every review interval after it.
  def review_dates(ends_before:, limit_on: nil)
    dates = []
    date = starts_on
    step = 0
    while (ends_before.nil? || date < ends_before) && (limit_on.nil? || date <= limit_on)
      dates << date
      step += 1
      date = starts_on >> (review_interval_months * step)
      break if dates.size > Loan::Simulator::MAX_PERIODS
    end
    dates
  end

  private
    def clear_unused_terms
      if fixed?
        self.reference_index = nil
        self.spread = nil
      elsif variable?
        self.base_rate = nil
      end
      self.floor_rate = 0 if floor_rate.nil?
    end
end
