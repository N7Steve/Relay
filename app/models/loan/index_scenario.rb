class Loan
  # What a projection assumes an index will be at future revisions.
  #
  # The default holds the latest published value flat: the one assumption that
  # needs no forecast. `shift` moves it by a fixed number of percentage points,
  # for "what if it rises by one point" questions. The result may be
  # negative, as an index can be; the revision applies the period's floor.
  class IndexScenario
    attr_reader :shift

    def self.flat
      new(shift: 0)
    end

    def initialize(shift: 0)
      @shift = BigDecimal(shift.to_s)
    end

    # The value assumed for `index_key` in `month`, given the latest stored
    # ReferenceRate (or nil when there is none, and so nothing to project from).
    def value_for(_index_key, _month, latest:)
      return nil if latest.nil?

      latest.published_value + shift
    end
  end
end
