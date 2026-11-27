# The rate a loan carried from one date onwards, frozen with every part that
# produced it: the base (a fixed rate, or the index value and spread), the bonus
# points applied and the floor.
#
# A recorded revision is history. Changing the loan's periods or bonuses later
# moves only revisions that have not been recorded yet, so interest already
# charged never changes after the fact. `confirmed` marks a revision the
# borrower checked against the lender's notice, or typed from it.
class Loan::RateRevision < ApplicationRecord
  self.table_name = "loan_rate_revisions"

  STATUSES = %w[calculated confirmed].freeze

  belongs_to :loan

  validates :effective_on, presence: true, uniqueness: { scope: :loan_id }
  validates :rate, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: Loan::MAX_INTEREST_RATE }
  validates :rate_kind, inclusion: { in: Loan::RatePeriod::KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :bonus_points, numericality: { greater_than_or_equal_to: 0 }

  scope :chronological, -> { order(:effective_on) }

  def confirmed? = status == "confirmed"
  def variable? = rate_kind == "variable"

  # The rate before bonuses: the fixed rate, or index plus spread.
  def unbonused_rate
    variable? ? (index_value.to_d + spread.to_d) : base_rate.to_d
  end
end
