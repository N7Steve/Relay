class Loan
  # Turns a loan's rate periods and bonuses into the sequence of rates it
  # carries, one revision per review date.
  #
  # Revisions whose date has arrived are RECORDED (`record_due!`) and from then
  # on read back exactly as stored: a later change to the periods, the bonuses
  # or the index series moves nothing that has already been charged. Revisions
  # still ahead are PROJECTED on every read, from the current periods and
  # bonuses and an index scenario -- by default the latest published value held
  # flat.
  #
  # ## Which index value a revision takes
  #
  # Spanish variable mortgages apply "the last index published at the revision
  # date": the monthly average of the month before the revision month, which the
  # Bank of Spain publishes in the first days of the revision month. A revision
  # is recorded once that month is stored. If it never arrives (no automatic
  # import, nothing typed) the revision falls back to the latest month stored
  # once INDEX_GRACE_DAYS have passed, and stays editable for the borrower to
  # correct from the lender's notice.
  class RateReviewer
    INDEX_GRACE_DAYS = 10

    attr_reader :loan, :scenario

    # `periods` and `bonuses` default to the loan's own. A scenario passes
    # hypothetical ones (unsaved records); recorded revisions are history and
    # are read as stored whatever is passed.
    def initialize(loan, scenario: IndexScenario.flat, periods: nil, bonuses: nil)
      @loan = loan
      @scenario = scenario
      @periods = periods
      @bonuses = bonuses
    end

    # Every revision over the loan's life, recorded ones as stored and the
    # rest projected, oldest first. Empty for a loan without rate periods.
    def timeline(as_of: Date.current)
      @timeline ||= {}
      @timeline[as_of] ||= begin
        recorded = recorded_revisions.index_by(&:effective_on)
        # Unrecorded dates are estimates whether or not they have arrived: a
        # revision still waiting for its index value is projected from the
        # latest one rather than leaving the earlier rate in force.
        @index_gaps = []
        projected = review_points.filter_map do |date, period|
          next if recorded.key?(date)

          build_revision(period, date, projected: true).tap do |revision|
            @index_gaps << date if revision.nil?
          end
        end
        (recorded.values + projected).sort_by(&:effective_on)
      end
    end

    # The revision in force on `date`, or nil before the first one.
    def revision_on(date, as_of: Date.current)
      timeline(as_of: as_of).reverse_each.find { |revision| revision.effective_on <= date }
    end

    # The first revision still ahead of `as_of`, projected, so never saved from
    # here. Nil once the loan has no revisions left.
    def next_revision(as_of: Date.current)
      timeline(as_of: as_of).find { |revision| revision.new_record? && revision.effective_on > as_of }
    end

    # Revisions whose date has arrived but which are not recorded yet: waiting
    # for their index value, or for the daily review to run.
    def pending_revisions(as_of: Date.current)
      timeline(as_of: as_of).select { |revision| revision.new_record? && revision.effective_on <= as_of }
    end

    # The first review date whose index value is not stored and cannot be
    # projected (no earlier value either). Rates from there on are unknown:
    # posting interest and re-sizing the Agenda instalment stop before it.
    def first_index_gap(as_of: Date.current)
      timeline(as_of: as_of)
      @index_gaps&.min
    end

    # Drops calculated revisions that no longer match the periods: dates that
    # are no longer review dates anywhere, and every date from `from` on when
    # a period starting there was added, changed or removed, so they are
    # recorded again from the corrected terms. Confirmed revisions stay: they
    # came from the lender's notice.
    def prune!(from: nil)
      review_dates = review_points.map(&:first).to_set
      stale = loan.rate_revisions.where(status: "calculated").select do |revision|
        !review_dates.include?(revision.effective_on) || (from && revision.effective_on >= from)
      end
      stale.each(&:destroy!)
      reset!
      stale
    end

    # Records the revisions whose date has arrived. Returns the ones created.
    def record_due!(as_of: Date.current)
      # Index values may have been stored since this reviewer last read them.
      @index_series = nil
      created = []
      recorded_dates = recorded_revisions.map(&:effective_on).to_set

      review_points.each do |date, period|
        next if date > as_of || recorded_dates.include?(date)

        revision = build_revision(period, date, projected: false, as_of: as_of)
        next if revision.nil?

        revision.save!
        created << revision
      end

      reset! if created.any?
      created
    end

    # Rate periods, oldest first, each paired with the date the next begins.
    def review_points
      @review_points ||= begin
        periods = (@periods || loan.rate_periods).sort_by(&:starts_on)
        maturity = loan.maturity_date

        # Without a term there is no end to review up to.
        if maturity.nil?
          []
        else
          periods.each_with_index.flat_map do |period, index|
            ends_before = periods[index + 1]&.starts_on || maturity
            period.review_dates(ends_before: ends_before).map { |date| [ date, period ] }
          end
        end
      end
    end

    def reset!
      @timeline = nil
      @review_points = nil
      @recorded_revisions = nil
      @index_gaps = nil
      @index_series = nil
      loan.rate_revisions.reset
    end

    private
      # Each index series read once per reviewer: a projection asks for a
      # value at every review date.
      def index_series(index_key)
        @index_series ||= {}
        @index_series[index_key] ||= ReferenceRate.for_index(index_key).order(:month).to_a
      end

      def recorded_revisions
        @recorded_revisions ||= loan.rate_revisions.sort_by(&:effective_on)
      end

      def bonus_points
        @bonus_points ||= (@bonuses || loan.rate_bonuses).select(&:active?).sum(BigDecimal("0")) { |bonus| bonus.points.to_d }
      end

      # nil when a recordable revision has no index value to take yet.
      def build_revision(period, date, projected:, as_of: nil)
        # A period that does not take bonuses (a rate quoted as final, or a new
        # lender's offer) is recorded with none.
        points = period.applies_bonuses? ? bonus_points : BigDecimal("0")
        # By id, not `loan:`: with has_many inversing an unsaved revision built
        # through the association joins `loan.rate_revisions` in memory, and a
        # projection would then read back as a recorded revision.
        attributes = {
          loan_id: loan.id,
          effective_on: date,
          rate_kind: period.rate_kind,
          bonus_points: points,
          status: "calculated"
        }

        base = if period.fixed?
          attributes[:base_rate] = period.base_rate
          period.base_rate.to_d
        else
          index_month, index_value = index_for(period.reference_index, date, projected: projected, as_of: as_of)
          return nil if index_value.nil?

          attributes.merge!(reference_index: period.reference_index, index_month: index_month,
                            index_value: index_value, spread: period.spread)
          index_value + period.spread.to_d
        end

        attributes[:rate] = [ base - points, period.floor_rate.to_d ].max
        Loan::RateRevision.new(attributes)
      end

      # [month, value] for a revision on `date`.
      def index_for(index_key, date, projected:, as_of:)
        wanted = date.beginning_of_month.prev_month
        stored = index_series(index_key).reverse_each.find { |row| row.month <= wanted }

        if stored&.month == wanted
          [ stored.month, stored.published_value ]
        elsif projected
          # Labelled with the month the value really comes from: the month the
          # revision will use is not published yet.
          value = scenario.value_for(index_key, wanted, latest: stored)
          value.nil? ? [ nil, nil ] : [ stored.month, value ]
        elsif stored && as_of >= date + INDEX_GRACE_DAYS
          [ stored.month, stored.published_value ]
        else
          [ nil, nil ]
        end
      end
  end
end
