class Loan
  # Posts the interest a loan charges to its own account, one entry per
  # payment date, so the account's balance is what the lender says is owed.
  #
  # Without it a loan account only sees the instalments paid into it, and each
  # one reduces the debt by its full amount -- interest included -- so the
  # balance runs ahead of the lender's by every euro of interest ever paid. With
  # it, each period's interest is charged on the date it is settled and the
  # instalment paid that day repays it first: the debt falls by the principal
  # alone, and the interest is visible as what it is.
  #
  # The instalments themselves are not touched. They stay the transfers they
  # are, from the account that pays them, so cash accounts, budgets and
  # matching see exactly what they saw before.
  #
  # ## When it runs
  #
  # On every recalculation of the loan account (Account::Recalculator), which
  # follows any change to its movements, a recorded revision or a change of
  # terms. Each run recomputes the whole history and brings the posted entries
  # in line: one entry per payment date, keyed by it, so running twice posts
  # nothing twice.
  #
  # ## How interest is worked out
  #
  # From the account's real history, not from the schedule: each day accrues on
  # that day's closing balance at the rate in force (Loan::RateResolver), under
  # the loan's accrual convention, and the total is rounded and posted on each
  # contractual payment date. An extra payment therefore lowers the interest
  # from the day it lands. An instalment paid a few days either side of its due
  # date is accrued as if paid on it (its value date), which is how the lender
  # books it. Each entry keeps how it was worked out (period, days, average
  # balance, rates) in `extra["loan_interest"]`, for the entry's detail view.
  #
  # Posted entries are the contract's and cannot be edited
  # (Entry::LoanContractGuard): a figure that differs from the lender's is put
  # right at its source -- the revision's rate, or the movements -- and the
  # ledger follows.
  class InterestLedger
    SOURCE = "loan_interest".freeze
    KIND = "loan_interest".freeze
    VALUE_DATE_WINDOW_DAYS = 4
    INSTALMENT_TOLERANCE = BigDecimal("0.05")

    def self.refresh!(account, as_of: Date.current)
      return unless account.accountable_type == "Loan"

      new(account.loan).refresh!(as_of: as_of)
    end

    attr_reader :loan

    def initialize(loan)
      @loan = loan
    end

    # [[date, amount]] the loan should have posted by `as_of`, oldest first.
    #
    # Nothing is posted for a period whose rate is not known: a revision still
    # waiting for its index value stops posting at the payment date before it,
    # rather than charging a rate the loan never had.
    def postings(as_of: Date.current)
      @details = {}
      origin = loan.origination_date
      return [] if origin.nil? || !loan.amortizable?

      liquidations = loan.payment_dates.select { |date| date <= as_of }
      gap = loan.structured_rate? ? loan.rate_reviewer.first_index_gap(as_of: as_of) : nil
      liquidations = liquidations.select { |date| date <= gap } if gap
      return [] if liquidations.empty?

      events = events_by_date(liquidations)
      walk_start, balance = starting_point(events, origin, liquidations)
      events = events.reject { |date, _| date < walk_start }
      liquidation_set = liquidations.select { |date| date > walk_start }.to_set
      return [] if liquidation_set.empty?

      last = liquidations.last
      accrued = BigDecimal("0")
      period = new_period(walk_start)
      posted = []
      day = walk_start

      while day <= last
        if liquidation_set.include?(day)
          amount = (loan.daily_accrual? ? accrued : monthly_interest(period[:opening_balance], day)).round(currency_precision)
          # A loan repaid early accrues nothing more; it gets no zero entries.
          if amount.nonzero?
            posted << [ day, amount ]
            @details[day] = detail_for(period, day)
            balance += amount
          end
          accrued = BigDecimal("0")
        end

        balance = apply_events(balance, events[day])
        period = new_period(day, balance) if liquidation_set.include?(day)
        period[:opening_balance] ||= balance

        if day >= origin && day < last
          rate = BigDecimal(resolver.accrual_rate_for(day).to_s)
          days_in_year = Date.leap?(day.year) ? 366 : 365
          accrued += balance * rate / 100 / days_in_year
          period[:balance_days] += balance
          period[:days] += 1
          period[:rates] << [ day, rate ] if period[:rates].empty? || period[:rates].last.last != rate
        end

        day += 1
      end

      posted
    end

    # How each posting from the last #postings run was worked out.
    def details
      @details || {}
    end

    # Brings the posted entries in line with #postings: entries for dates that
    # are no longer payment dates go, changed amounts are corrected and new
    # ones are created. With tracking off, every posted entry goes. Writes
    # through the loan's own door (Loan::ContractWrites).
    def refresh!(as_of: Date.current)
      computed = loan.interest_tracking? ? postings(as_of: as_of) : []
      existing = posted_entries.index_by(&:external_id)
      wanted = computed.to_h { |date, amount| [ date.iso8601, [ date, amount ] ] }

      ContractWrites.allow do
        existing.each do |key, entry|
          entry.destroy! unless wanted.key?(key)
        end

        wanted.each do |key, (date, amount)|
          entry = existing[key]
          detail = details[date]
          if entry.nil?
            create_entry!(date, amount, detail)
          else
            entry.update_columns(amount: amount, updated_at: Time.current) if entry.amount != amount
            write_detail(entry.entryable, detail)
          end
        end
      end

      computed
    end

    private
      def account
        loan.account
      end

      def resolver
        @resolver ||= RateResolver.for(loan)
      end

      def currency_precision
        @currency_precision ||= Money::Currency.new(account.currency).default_precision || 2
      end

      def posted_entries
        @posted_entries ||= account.entries.where(source: SOURCE).includes(:entryable).to_a
      end

      def new_period(from, opening_balance = nil)
        { from: from, opening_balance: opening_balance, balance_days: BigDecimal("0"), days: 0, rates: [] }
      end

      def detail_for(period, to)
        days = period[:days]
        {
          "from" => period[:from].iso8601,
          "to" => to.iso8601,
          "days" => days,
          "average_balance" => (days.positive? ? period[:balance_days] / days : period[:opening_balance].to_d).round(currency_precision).to_s("F"),
          "rates" => period[:rates].map { |date, rate| [ date.iso8601, rate.to_s("F") ] },
          "accrual" => loan.interest_accrual
        }
      end

      def write_detail(transaction, detail)
        return if detail.nil? || transaction.extra&.dig("loan_interest") == detail

        transaction.update_columns(extra: (transaction.extra || {}).merge("loan_interest" => detail), updated_at: Time.current)
      end

      # Monthly accrual, as the schedule charges it: the period's opening
      # balance at the rate in force when the period opened, over twelve.
      def monthly_interest(period_balance, liquidation)
        opened = loan.payment_dates.reverse.find { |date| date < liquidation } || loan.origination_date
        period_balance.to_d * BigDecimal(resolver.accrual_rate_for(opened).to_s) / 100 / 12
      end

      # Where the walk starts and what was owed then. Normally origination and
      # the amount lent (or a valuation on or before it). A loan whose
      # tracked history starts later -- an old mortgage added today with its
      # current balance as the opening valuation -- starts at the payment date
      # on or before that valuation, with the valuation's amount: the
      # principal does not move between instalments, and nothing is invented
      # for the years before the account knew the balance.
      def starting_point(events, origin, liquidations)
        first_valuation = events.select { |_, entries| entries.any?(&:valuation?) }.keys.min
        if first_valuation && first_valuation > origin && events.keys.min == first_valuation
          anchor = events[first_valuation].find(&:valuation?)
          period_open = liquidations.reverse.find { |date| date <= first_valuation } || origin
          return [ period_open, anchor.amount.to_d ]
        end

        [ [ origin, events.keys.min ].compact.min, opening_balance(events, origin) ]
      end

      # Every entry that moves the balance, except the interest this ledger
      # posts, keyed by the date it counts on.
      def events_by_date(liquidations)
        account.entries.eligible_for_balance
          .where("entries.source IS DISTINCT FROM ?", SOURCE)
          .includes(:entryable)
          .to_a
          .group_by { |entry| value_date(entry, liquidations) }
      end

      # An instalment paid near its due date counts on the due date. Only one
      # the size of the instalment due: an extra repayment made the same week
      # lowers the balance from the day it actually lands.
      def value_date(entry, liquidations)
        return entry.date unless entry.transaction? && entry.amount.negative? && entry.entryable.transfer?

        nearest = liquidations.min_by { |date| (date - entry.date).abs }
        return entry.date if nearest.nil? || (nearest - entry.date).abs > VALUE_DATE_WINDOW_DAYS

        due = loan.payment_due_on(nearest)&.amount
        return entry.date if due.nil? || (entry.amount.abs - due).abs > due * INSTALMENT_TOLERANCE

        nearest
      end

      # What was owed before the first event: a valuation on or before
      # origination sets it when there is one; otherwise the amount lent.
      def opening_balance(events, origin)
        anchored = events.keys.min.present? && events.keys.min <= origin &&
          events.select { |date, _| date <= origin }.values.flatten.any?(&:valuation?)
        anchored ? BigDecimal("0") : loan.original_balance.amount.to_d
      end

      def apply_events(balance, entries)
        return balance if entries.blank?

        valuation = entries.find(&:valuation?)
        return valuation.amount.to_d if valuation

        entries.sum(balance) { |entry| entry.amount.to_d }
      end

      def create_entry!(date, amount, detail)
        account.entries.create!(
          date: date,
          amount: amount,
          currency: account.currency,
          name: entry_name,
          source: SOURCE,
          external_id: date.iso8601,
          entryable: Transaction.new(kind: KIND, extra: detail ? { "loan_interest" => detail } : {})
        )
      end

      def entry_name
        @entry_name ||= I18n.with_locale(account.family.locale.presence || I18n.default_locale) do
          I18n.t("loans.interest_ledger.entry_name")
        end
      end
  end
end
