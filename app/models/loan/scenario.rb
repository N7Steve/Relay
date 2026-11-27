class Loan
  # "What if" for a loan, computed and never saved: the loan as it stands
  # against the same loan with a change of terms (switching to a fixed rate,
  # or to another lender's variable offer) and/or an extra repayment, under an
  # assumed index path.
  #
  # Both sides run the same engine as the real schedule. Recorded revisions and
  # prepayments are history and are kept on both; the hypothetical period
  # replaces every period from its start date, and its rate is taken as final
  # (bonuses only apply when `keep_bonuses` says the new terms keep them).
  # Figures compare what is still to be paid after `as_of`.
  class Scenario
    include ActiveModel::Model
    include ActiveModel::Attributes

    CHANGE_KINDS = %w[fixed variable].freeze
    INDEX_SHIFTS = [ -1, 0, 1, 2 ].freeze

    attribute :index_shift, :decimal, default: 0
    attribute :change_kind, :string
    attribute :change_on, :date
    attribute :change_rate, :decimal
    attribute :change_spread, :decimal
    attribute :change_cost, :decimal, default: 0
    attribute :keep_bonuses, :boolean, default: false
    attribute :prepayment_amount, :decimal
    attribute :prepayment_on, :date
    attribute :prepayment_mode, :string, default: "reduce_term"
    attribute :prepayment_fee, :decimal, default: 0

    Outcome = Data.define(:next_payment, :payment_after_change, :remaining_interest, :remaining_paid, :payoff_date, :costs) do
      def total_cost
        remaining_paid + costs
      end
    end

    attr_reader :loan, :as_of

    validates :change_kind, inclusion: { in: CHANGE_KINDS }, allow_blank: true
    validates :change_on, presence: true, if: :rate_change?
    validates :change_rate, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: Loan::MAX_INTEREST_RATE }, if: -> { change_kind == "fixed" }
    validates :change_spread, presence: true, numericality: { greater_than: -Loan::MAX_INTEREST_RATE, less_than_or_equal_to: Loan::MAX_INTEREST_RATE }, if: -> { change_kind == "variable" }
    validates :change_cost, :prepayment_fee, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :prepayment_amount, numericality: { greater_than: 0 }, allow_nil: true
    validates :prepayment_on, presence: true, if: :prepayment?
    validates :prepayment_mode, inclusion: { in: Loan::Prepayment::MODES }
    validates :index_shift, numericality: { greater_than_or_equal_to: -10, less_than_or_equal_to: 10 }
    validate :rate_change_needs_structured_loan

    def initialize(loan:, as_of: Date.current, **attributes)
      @loan = loan
      @as_of = as_of
      super(**attributes)
      apply_defaults
    end

    def rate_change?
      change_kind.present?
    end

    def prepayment?
      prepayment_amount.present? && prepayment_amount.positive?
    end

    def changes_anything?
      rate_change? || prepayment?
    end

    def applicable?
      loan.amortizable?
    end

    def baseline
      @baseline ||= outcome_for(baseline_schedule(index_shift), costs: BigDecimal("0"))
    end

    def proposal
      return nil unless changes_anything? && valid?

      @proposal ||= outcome_for(proposal_schedule(index_shift), costs: one_off_costs)
    end

    # Interest saved after costs: positive means the change pays for itself.
    def net_saving
      return nil if proposal.nil?

      (baseline.remaining_interest - proposal.remaining_interest) - proposal.costs
    end

    def months_saved
      return nil if proposal.nil? || baseline.payoff_date.nil? || proposal.payoff_date.nil?

      (baseline.payoff_date.year * 12 + baseline.payoff_date.month) - (proposal.payoff_date.year * 12 + proposal.payoff_date.month)
    end

    # The same comparison under several index paths, so a fixed offer can be
    # read against the variable rate it would replace.
    def sensitivity
      @sensitivity ||= INDEX_SHIFTS.map do |shift|
        shift = BigDecimal(shift.to_s)
        base = outcome_for(baseline_schedule(shift), costs: BigDecimal("0"))
        proposed = changes_anything? && valid? ? outcome_for(proposal_schedule(shift), costs: one_off_costs) : nil
        { shift: shift, baseline: base, proposal: proposed }
      end
    end

    def latest_index
      @latest_index ||= ReferenceRate.for_index(index_key).order(month: :desc).first
    end

    def currency
      loan.account.currency
    end

    private
      def index_key
        loan.rate_periods.filter_map(&:reference_index).last || ReferenceRate::INDEXES.keys.first
      end

      # Sensible starting values for an empty form: the change takes effect on
      # the next revision, the extra repayment on the next instalment date.
      def apply_defaults
        next_revision = loan.structured_rate? ? loan.rate_reviewer.next_revision(as_of: as_of)&.effective_on : nil
        next_payment = loan.payment_dates.find { |date| date > as_of }
        self.change_on ||= next_revision || next_payment
        self.prepayment_on ||= next_payment
      end

      # The date the comparison quotes an instalment after: the change asked
      # about, or else the next revision.
      def reference_date
        @reference_date ||= [ (change_on if rate_change?), (prepayment_on if prepayment?) ].compact.min ||
          (loan.rate_reviewer.next_revision(as_of: as_of)&.effective_on if loan.structured_rate?)
      end

      def one_off_costs
        (rate_change? ? change_cost.to_d : 0) + (prepayment? ? prepayment_fee.to_d : 0)
      end

      def baseline_schedule(shift)
        Loan::AmortizationSchedule.for(loan, rate_reviewer: reviewer(shift))
      end

      def proposal_schedule(shift)
        Loan::AmortizationSchedule.for(
          loan,
          rate_reviewer: reviewer(shift, periods: proposal_periods),
          prepayments: loan.prepayment_events + proposal_prepayments
        )
      end

      def reviewer(shift, periods: nil)
        return nil unless loan.structured_rate?

        Loan::RateReviewer.new(loan, scenario: Loan::IndexScenario.new(shift: shift), periods: periods)
      end

      def proposal_periods
        return nil unless rate_change? && loan.structured_rate?

        kept = loan.rate_periods.select { |period| period.starts_on < change_on }
        kept + [ hypothetical_period ]
      end

      def hypothetical_period
        # By id: built through `loan:` it would join `loan.rate_periods` in
        # memory (has_many inversing) and leak into the real schedule.
        Loan::RatePeriod.new(
          loan_id: loan.id,
          starts_on: change_on,
          rate_kind: change_kind,
          base_rate: (change_rate if change_kind == "fixed"),
          reference_index: (index_key if change_kind == "variable"),
          spread: (change_spread if change_kind == "variable"),
          review_interval_months: 12,
          floor_rate: 0,
          applies_bonuses: keep_bonuses
        )
      end

      def proposal_prepayments
        return [] unless prepayment?

        [ { date: prepayment_on, amount: prepayment_amount, mode: prepayment_mode } ]
      end

      def outcome_for(schedule, costs:)
        return nil if schedule.nil?

        ahead = schedule.payments.select { |payment| payment.date > as_of }
        after_change = ahead.find { |payment| payment.date > reference_date } if reference_date

        Outcome.new(
          next_payment: ahead.first&.payment,
          payment_after_change: after_change&.payment,
          remaining_interest: ahead.sum(BigDecimal("0")) { |payment| payment.interest.amount },
          remaining_paid: ahead.sum(BigDecimal("0")) { |payment| payment.payment.amount + payment.prepayment.amount },
          payoff_date: schedule.payoff_date,
          costs: costs
        )
      end

      def rate_change_needs_structured_loan
        errors.add(:change_kind, :requires_structured_rate) if rate_change? && !loan.structured_rate?
      end
  end
end
