class Loan
  # The period engine. Walks a payment schedule, charging interest and applying
  # payments, and returns a SimulationResult.
  #
  # It takes values and callables rather than a Loan, so the contracted schedule
  # and (later) a projection from today's balance can share one loop instead of
  # growing two implementations that drift.
  #
  # ## Accrual is monthly
  #
  # One interest charge per period, on the balance outstanding when the period
  # opened. Daily accrual is a different engine and is deliberately not here.
  #
  # ## Two rates, not one
  #
  # A period is bounded by two dates, and on a variable loan they can sit either
  # side of a rate change. Which rate applies depends on what is being asked:
  #
  #   * **Interest** for the period [previous payment date, this payment date)
  #     accrues at the rate in force when the period **opened**. A rate that
  #     becomes effective on this period's closing date belongs to the NEXT
  #     window, not to the month that has already run at the old rate.
  #   * **Payment sizing** uses the rate in force **on** the payment date, so a
  #     change effective on a payment date resizes that payment.
  #
  # Reading a single rate for both re-rates the period ending on the boundary --
  # the borrower is charged a rate that did not apply for any day of the month
  # being billed. Keeping them apart is the whole reason `accrual_rate_for` is
  # called twice with different dates below.
  #
  # Under monthly accrual a rate change *mid*-period cannot move that period's
  # interest: there is one charge, computed at the period's opening rate. It
  # takes effect from the following period. That is a property of monthly
  # accrual, not an approximation to be corrected here.
  #
  # ## Daily accrual
  #
  # `day_count: :actual_365` charges each day of the period at the rate in
  # force that day, over the days of its year (366 in a leap year), and rounds
  # once per period -- the "capital x rate x days / 36,500 (36,600 in leap
  # years)" formula of Spanish mortgage deeds. A February then costs less than
  # a January on the same balance, as on the lender's own statement. The level
  # payment is still sized with the annuity formula at rate / 12, which is how
  # those deeds define the instalment, so the final payment absorbs the small
  # difference between the two conventions.
  #
  # ## When a rate change resizes the payment
  #
  # `payment_sizing: :payment_date` (the default) sizes each payment at the
  # rate in force on its date, as described above. `:period_opening` sizes it
  # at the rate its own period accrues at, so a revision effective ON a payment
  # date leaves that payment as it was and resizes the next one -- a lender
  # revising a mortgage on the anniversary of its first payment.
  #
  # ## Prepayments
  #
  # `prepayments:` are extra repayments, each { date:, amount:, mode: }. One
  # dated inside a period's window [opening, closing) lowers the balance from
  # that day: under daily accrual the period is charged on the balance each day
  # actually carried (the deed's "average drawn balance"); under monthly
  # accrual it takes effect from the next period. What happens next is the
  # borrower's choice, as Spanish deeds offer it:
  #
  #   :reduce_payment  the term stays; the instalment is re-sized over the
  #                    payments left
  #   :reduce_term     the instalment stays; the loan ends sooner, and later
  #                    rate revisions re-size over that shorter term
  class Simulator
    # Guards a runaway schedule: a hundred years of monthly payments. Refused
    # outright rather than truncated -- silently walking the first 1,200 of a
    # longer schedule returns totals and a payoff date describing a loan that
    # was never asked for, and loses the remaining balance without saying so.
    MAX_PERIODS = 1200

    # How the repayment behaves from one period to the next:
    #
    #   :reamortize  sized from the balance in front of it, and re-sized
    #                whenever the sizing rate moves -- what a lender does to a
    #                contracted schedule
    #   :hold        one figure, seeded or sized on the first period, held to
    #                the end whatever the rate does
    #   :scheduled   asked for every period from a callable, regardless of the
    #                balance -- what a projection uses to pay the CONTRACT's
    #                repayment against a balance that is no longer the
    #                contracted one, so a borrower who is ahead finishes early
    #                instead of being re-sized back onto the original maturity
    PAYMENT_STRATEGIES = %i[reamortize hold scheduled].freeze
    DAY_COUNTS = %i[monthly actual_365].freeze
    PAYMENT_SIZINGS = %i[payment_date period_opening].freeze
    PREPAYMENT_MODES = %i[reduce_payment reduce_term].freeze

    # Built once: `monthly_rate` runs twice per period, up to MAX_PERIODS times
    # per simulation. The two-step division is kept as it was so results stay
    # bit-identical to the schedules already asserted in the tests.
    PERCENT = BigDecimal("100")
    MONTHS_PER_YEAR = BigDecimal("12")

    def initialize(
      starting_balance:,
      accrual_start_date:,
      payment_schedule:,
      accrual_rate_for:,
      currency_precision:,
      re_amortisation_events: nil,
      payment_strategy: :reamortize,
      payment_amount: nil,
      settle_at_schedule_end: true,
      day_count: :monthly,
      payment_sizing: :payment_date,
      prepayments: []
    )
      @starting_balance = BigDecimal(starting_balance.to_s)
      @accrual_start_date = accrual_start_date
      @payment_schedule = payment_schedule.to_a.freeze
      @accrual_rate_for = callable!(accrual_rate_for, :accrual_rate_for)
      @re_amortisation_events = callable!(
        re_amortisation_events || ->(_from, _to) { [] }, :re_amortisation_events
      )
      @currency_precision = currency_precision
      @payment_strategy = payment_strategy.to_sym
      # A caller-supplied repayment. Under :hold and :reamortize a number that
      # seeds the run; under :scheduled a callable, asked every period for the
      # amount the contract requires then -- see #run.
      @payment_amount =
        if payment_amount.respond_to?(:call) then payment_amount
        elsif payment_amount.nil? then nil
        else BigDecimal(payment_amount.to_s)
        end
      @settle_at_schedule_end = settle_at_schedule_end
      @day_count = day_count.to_sym
      @payment_sizing = payment_sizing.to_sym
      @prepayments = prepayments.map do |prepayment|
        {
          date: prepayment.fetch(:date),
          amount: BigDecimal(prepayment.fetch(:amount).to_s),
          mode: prepayment.fetch(:mode).to_sym
        }
      end.sort_by { |prepayment| prepayment[:date] }.freeze
      if (unknown = @prepayments.map { |prepayment| prepayment[:mode] } - PREPAYMENT_MODES).any?
        raise ArgumentError, "unsupported prepayment mode: #{unknown.first.inspect}"
      end

      raise ArgumentError, "payment schedule must not be empty" if @payment_schedule.empty?
      if @payment_schedule.length > MAX_PERIODS
        raise ArgumentError,
          "payment schedule has #{@payment_schedule.length} periods (#{@payment_schedule.first} to #{@payment_schedule.last}), " \
          "more than the #{MAX_PERIODS} allowed"
      end
      unless PAYMENT_STRATEGIES.include?(@payment_strategy)
        raise ArgumentError, "unsupported payment strategy: #{@payment_strategy.inspect}"
      end
      raise ArgumentError, "unsupported day count: #{@day_count.inspect}" unless DAY_COUNTS.include?(@day_count)
      raise ArgumentError, "unsupported payment sizing: #{@payment_sizing.inspect}" unless PAYMENT_SIZINGS.include?(@payment_sizing)
      if (@payment_strategy == :scheduled) != @payment_amount.respond_to?(:call)
        raise ArgumentError, ":scheduled takes a callable payment_amount; the other strategies take a number"
      end
    end

    def run
      balance = @starting_balance
      payments = []
      payment = nil
      previous_sizing_rate = nil
      # The number of payments the contract runs to. A reduce-term prepayment
      # brings it forward, and re-sizing on a later revision spreads the
      # balance over what is left of THAT term, not the original one.
      term_end = @payment_schedule.length
      (0...@payment_schedule.length).each do |index|
        break if balance <= 0

        payment_date = @payment_schedule[index]
        period_start = index.zero? ? @accrual_start_date : @payment_schedule[index - 1]
        prepaid_in_period = @prepayments.select { |prepayment| prepayment[:date] >= period_start && prepayment[:date] < payment_date }
        prepaid = [ prepaid_in_period.sum(BigDecimal("0")) { |prepayment| prepayment[:amount] }, balance ].min

        # See the class comment: opening rate charges the period, closing rate
        # sizes the payment.
        accrual_rate = monthly_rate(@accrual_rate_for.call(period_start))
        sizing_rate = @payment_sizing == :period_opening ? accrual_rate : monthly_rate(rate_on(payment_date))

        # Interest first, on the balance the period OPENED with: one charge per
        # period under monthly accrual. Sizing needs it when the two rates
        # differ, see below.
        interest = period_interest(balance, period_start, payment_date, accrual_rate, prepaid_in_period)
        opening_balance = balance
        balance -= prepaid
        prepayment_mode = prepaid.positive? ? prepaid_in_period.last[:mode] : nil

        if @payment_strategy == :scheduled
          # The contract's repayment for THIS period, whatever balance is in
          # front of it. Sizing from the balance would shrink a borrower who is
          # ahead back onto the original maturity; paying what the contract
          # asks is how they finish sooner.
          payment = BigDecimal(@payment_amount.call(
            index: index,
            balance: balance,
            sizing_rate: sizing_rate,
            remaining_payments: term_end - index
          ).to_s)
        else
          # Resize only when the sizing rate actually moves. Recomputing every
          # period would be arithmetically identical while the rate holds, but
          # it would also silently absorb a payment the borrower is contracted
          # to, which is what `:hold` exists to refuse.
          if payment.nil?
            # A supplied amount seeds the run -- a projection opens on the
            # repayment the borrower is contracted to, not one re-derived from
            # today's balance, which would make every loan look on track.
            payment = @payment_amount
          end
          # `previous_sizing_rate.nil?` guards the first period: there is no
          # earlier rate to have moved away from, so the opening rate is not a
          # rate CHANGE. Without it, a seeded repayment is overwritten on the
          # very first period it was supposed to govern.
          rate_moved = !previous_sizing_rate.nil? && sizing_rate != previous_sizing_rate
          # When the period straddles the change -- accrued at the old rate,
          # sized at the new -- the annuity formula alone over-covers this
          # period and the payment is not level to maturity (a final
          # settlement thousands short). The sizing is told what this period
          # actually charged so the figure covers it and amortises the rest
          # evenly.
          reduce_payment = @payment_strategy != :hold && prepayment_mode == :reduce_payment
          if prepayment_mode == :reduce_term && (payment.nil? || (@payment_strategy == :reamortize && rate_moved))
            # A revision landing with a shorten-the-term prepayment sizes the
            # instalment as the lender does, on the balance before the
            # prepayment; the prepayment then keeps it and shortens the term.
            # Sized on the reduced balance it would spread over the old term
            # and shorten nothing.
            payment = AmortizationMath.level_payment(
              balance: opening_balance,
              monthly_rate: sizing_rate,
              remaining_payments: [ term_end - index, 1 ].max,
              currency_precision: @currency_precision
            )
          elsif payment.nil? || (@payment_strategy == :reamortize && rate_moved) || reduce_payment
            payment = AmortizationMath.level_payment(
              balance: balance,
              monthly_rate: sizing_rate,
              # At least this one: a rate change landing at or past a
              # shortened end with cents still owed must settle them, not
              # size a zero payment and let the balance grow.
              remaining_payments: [ term_end - index, 1 ].max,
              currency_precision: @currency_precision,
              # A period that straddled a prepayment was charged on more than
              # the balance now in front of it, so it is passed as charged.
              first_period_interest: (interest if sizing_rate != accrual_rate || prepaid.positive?)
            )
          end

          if prepayment_mode == :reduce_term
            term_end = [ index + AmortizationMath.payments_to_clear(
              balance: balance, payment: payment, monthly_rate: sizing_rate, first_period_interest: interest
            ), term_end ].min
          end
        end
        previous_sizing_rate = sizing_rate

        final = (@settle_at_schedule_end && index == @payment_schedule.length - 1) ||
          payment >= balance + interest

        step = AmortizationMath.step(
          balance: balance,
          payment: payment,
          monthly_rate: accrual_rate,
          currency_precision: @currency_precision,
          final: final,
          interest: interest
        )

        # Two rates on the row, named for what each did: `interest_rate` is
        # the one the interest column was computed with, so a reader who
        # recomputes beginning_balance * rate / 12 gets this row's figure;
        # `sizing_rate` is the one the payment was sized at. They differ only
        # on a row whose period straddles a rate change.
        payments << {
          payment_number: index + 1,
          payment_date: payment_date,
          interest_rate: BigDecimal(@accrual_rate_for.call(period_start).to_s),
          sizing_rate: BigDecimal((@payment_sizing == :period_opening ? @accrual_rate_for.call(period_start) : rate_on(payment_date)).to_s),
          prepayment: prepaid.round(@currency_precision),
          **step,
          beginning_balance: opening_balance.round(@currency_precision)
        }

        balance = step[:ending_balance]
      end

      SimulationResult.new(
        payments: payments,
        converged: balance.zero?,
        balloon_amount: balance,
        currency_precision: @currency_precision
      )
    end

    # Interest a constant `balance` accrues over [from, to), each day at the
    # rate in force that day over the days of its year, rounded once to the
    # currency.
    def self.daily_interest(balance:, from:, to:, rate_for:, currency_precision:)
      accrued_interest(balance: balance, from: from, to: to, rate_for: rate_for).round(currency_precision)
    end

    # The same, unrounded. Days are grouped into runs that share a rate and a
    # year length, so a period costs one multiplication per run rather than
    # one per day.
    def self.accrued_interest(balance:, from:, to:, rate_for:)
      total = BigDecimal("0")
      run_key = nil
      run_days = 0
      day = from

      while day < to
        key = [ BigDecimal(rate_for.call(day).to_s), Date.leap?(day.year) ? 366 : 365 ]
        if key != run_key
          total += balance * run_key.first * run_days / PERCENT / run_key.last if run_key
          run_key = key
          run_days = 0
        end
        run_days += 1
        day += 1
      end

      total += balance * run_key.first * run_days / PERCENT / run_key.last if run_key
      total
    end

    private
      # Under daily accrual a prepayment lowers the balance from its own date;
      # under monthly accrual it takes effect from the next period.
      def period_interest(balance, period_start, payment_date, accrual_rate, prepayments)
        unless @day_count == :actual_365
          # Paid on the day the period opens, it lowers this period's balance.
          opening_prepaid = prepayments.select { |prepayment| prepayment[:date] == period_start }.sum(BigDecimal("0")) { |prepayment| prepayment[:amount] }
          return ([ balance - opening_prepaid, BigDecimal("0") ].max * accrual_rate).round(@currency_precision)
        end

        total = BigDecimal("0")
        segment_start = period_start
        segment_balance = balance
        prepayments.each do |prepayment|
          total += self.class.accrued_interest(balance: segment_balance, from: segment_start, to: prepayment[:date], rate_for: @accrual_rate_for)
          segment_start = prepayment[:date]
          segment_balance = [ segment_balance - prepayment[:amount], BigDecimal("0") ].max
        end
        total += self.class.accrued_interest(balance: segment_balance, from: segment_start, to: payment_date, rate_for: @accrual_rate_for)
        total.round(@currency_precision)
      end

      # The contracted rate on a given payment date: a re-amortisation event
      # effective that day, otherwise whatever the rate curve says.
      def rate_on(date)
        event = re_amortisation_rates.reverse.find { |effective, _| effective <= date }
        event ? event.last : @accrual_rate_for.call(date)
      end

      def re_amortisation_rates
        @re_amortisation_rates ||= @re_amortisation_events
          .call(@payment_schedule.first, @payment_schedule.last)
          .map { |event| [ event.fetch(:date), event.fetch(:rate) ] }
          .sort_by(&:first)
      end

      # `annual_percentage` is whatever the caller's rate callable returned --
      # an Integer in the tests, a BigDecimal from RateResolver -- so the
      # coercion at this boundary stays.
      def monthly_rate(annual_percentage)
        (BigDecimal(annual_percentage.to_s) / PERCENT) / MONTHS_PER_YEAR
      end

      def callable!(value, name)
        raise ArgumentError, "#{name} must respond to #call" unless value.respond_to?(:call)

        value
      end
  end
end
