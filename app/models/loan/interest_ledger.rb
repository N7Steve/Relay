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
  # ## How interest is worked out
  #
  # From the account's real history, not from the schedule: each day accrues on
  # that day's closing balance at the rate in force (Loan::RateResolver), under
  # the loan's accrual convention, and the total is rounded and posted on each
  # contractual payment date. An extra payment therefore lowers the interest
  # from the day it lands, and a missed one raises it. An instalment paid a few
  # days either side of its due date is accrued as if paid on it (its value
  # date), which is how the lender books it.
  #
  # Valuations are absolute, as in the balance calculation: one resets the
  # balance on its date.
  #
  # An entry the user has edited keeps its amount and is used as posted, so a
  # figure copied from the lender's receipt is never overwritten.
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
      period_balance = nil
      posted = []
      day = walk_start

      while day <= last
        if liquidation_set.include?(day)
          amount = pinned_amounts.fetch(day) { (loan.daily_accrual? ? accrued : monthly_interest(period_balance, day)).round(currency_precision) }
          # A loan repaid early accrues nothing more; it gets no zero entries.
          if amount.nonzero? || pinned_amounts.key?(day)
            posted << [ day, amount ]
            balance += amount
          end
          accrued = BigDecimal("0")
        end

        balance = apply_events(balance, events[day])
        period_balance = balance if period_balance.nil? || liquidation_set.include?(day)

        if day >= origin && day < last
          days_in_year = Date.leap?(day.year) ? 366 : 365
          accrued += balance * BigDecimal(resolver.accrual_rate_for(day).to_s) / 100 / days_in_year
        end

        day += 1
      end

      posted
    end

    # Brings the posted entries in line with #postings. Entries for dates that
    # are no longer payment dates go; changed amounts are corrected unless the
    # user edited them. With tracking off, every posted entry goes.
    def refresh!(as_of: Date.current)
      computed = loan.interest_tracking? ? postings(as_of: as_of) : []
      existing = posted_entries.index_by(&:external_id)
      wanted = computed.to_h { |date, amount| [ date.iso8601, [ date, amount ] ] }

      # An entry on a date that is no longer a payment date goes, even with
      # its amount pinned: kept, its interest would be counted next to the
      # entry that now covers the same days.
      existing.each do |key, entry|
        entry.destroy! unless wanted.key?(key)
      end

      wanted.each do |key, (date, amount)|
        entry = existing[key]
        if entry.nil?
          create_entry!(date, amount)
        elsif !amount_pinned?(entry) && entry.amount != amount
          entry.update_columns(amount: amount, updated_at: Time.current)
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
        @posted_entries ||= account.entries.where(source: SOURCE).to_a
      end

      # Amounts the user edited by hand (the figure on the lender's receipt).
      # Only an edited AMOUNT pins the entry: a note or a tag added to it must
      # not stop it following later revisions and payments.
      def pinned_amounts
        @pinned_amounts ||= posted_entries.select { |entry| amount_pinned?(entry) }.to_h { |entry| [ entry.date, entry.amount.to_d ] }
      end

      def amount_pinned?(entry)
        entry.locked?(:amount)
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

      def create_entry!(date, amount)
        account.entries.create!(
          date: date,
          amount: amount,
          currency: account.currency,
          name: entry_name,
          source: SOURCE,
          external_id: date.iso8601,
          entryable: Transaction.new(kind: KIND)
        )
      end

      def entry_name
        @entry_name ||= I18n.with_locale(account.family.locale.presence || I18n.default_locale) do
          I18n.t("loans.interest_ledger.entry_name")
        end
      end
  end
end
