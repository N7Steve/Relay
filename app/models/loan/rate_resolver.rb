class Loan
  # Answers "what rate applies?" for a loan, without making Loan::Simulator
  # depend on the Loan model.
  #
  # A fixed loan answers the same rate for every date. A variable loan reads
  # its recorded rate changes.
  #
  # ## Why two questions, not one
  #
  # A rate change moves two different things on different days, and conflating
  # them bills the borrower wrongly:
  #
  #   * `accrual_rate_for(date)` -- the rate in force on a given day. The
  #     simulator asks this at each period's OPENING date, so a change takes
  #     effect from the period that begins on it.
  #   * `re_amortisation_events` -- the dates on which the contracted repayment
  #     is resized. The simulator applies these ON the payment date.
  #
  # Both read the same recorded changes; they are separate methods because the
  # simulator must be able to be told different answers. A rate that moves what
  # is charged without immediately moving what is owed each month is exactly
  # what a variable loan does between payment dates.
  class RateResolver
    def self.for(loan)
      new(loan)
    end

    # `rate_reviewer` lets a scenario substitute hypothetical periods or an
    # index path; by default the loan's own reviewer answers.
    def initialize(loan, rate_reviewer: nil)
      @loan = loan
      @rate_reviewer = rate_reviewer
    end

    # The rate in force on `date`: the latest change effective on or before it,
    # falling back to the loan's own rate before any change applies.
    #
    # A loan with structured rate periods reads its revisions instead -- the
    # recorded ones, then projections -- and nothing else.
    def accrual_rate_for(date)
      return structured_rate_for(date) if loan.structured_rate?
      return loan.interest_rate unless loan.variable_rate_type?

      rate_changes.reverse_each.find { |effective_date, _| effective_date <= date }&.last || loan.interest_rate
    end

    # Every recorded change falling inside [from_date, to_date], as the
    # {date:, rate:} pairs the simulator consumes. Bounds are inclusive at both
    # ends: a change effective on the final payment date still resizes it.
    #
    # None for a structured loan: its schedule is sized at each period's own
    # rate (`payment_sizing: :period_opening`), so a revision effective on a
    # payment date resizes the payment AFTER it, as a lender's revision does.
    def re_amortisation_events(from_date, to_date)
      return [] if loan.structured_rate?
      return [] unless loan.variable_rate_type?

      rate_changes.filter_map do |effective_date, rate|
        next unless effective_date >= from_date && effective_date <= to_date

        { date: effective_date, rate: rate }
      end
    end

    private
      attr_reader :loan

      # Revisions as [date, rate] pairs, read once: the daily-accrual simulator
      # asks for a rate on every day of the loan's life.
      def structured_rates
        @structured_rates ||= (@rate_reviewer || loan.rate_reviewer).timeline
          .map { |revision| [ revision.effective_on, revision.rate.to_d ] }
      end

      # Binary search: the daily simulator asks for every day of the loan.
      def structured_rate_for(date)
        index = structured_rates.bsearch_index { |effective_on, _| effective_on > date }
        position = (index || structured_rates.length) - 1

        # Before the first period starts the earliest known rate applies, so a
        # period entered a few days after origination charges those days too.
        return structured_rates.first&.last || loan.interest_rate || BigDecimal("0") if position.negative?

        structured_rates[position].last
      end

      # Loan#variable_rates, read once. The simulator asks for a rate up to
      # three times a period over as many as 1,200 periods; reparsing and
      # re-sorting the column each time is the kind of cost that only shows up
      # on the longest loans. Parsing stays in Loan, so this reader and that one
      # cannot drift apart.
      def rate_changes
        @rate_changes ||= loan.variable_rates
      end
  end
end
