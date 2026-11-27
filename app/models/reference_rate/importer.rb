# Fetches the published values of the indices loans are revised against and
# stores them as ReferenceRate rows. Only runs with the installation's
# `reference_rates` external capability enabled; otherwise values are typed in
# by hand from the lender's notice.
class ReferenceRate::Importer
  # How far back an empty series starts: enough for any revision a loan
  # tracked today could still be recording.
  INITIAL_HISTORY_MONTHS = 36
  # Months re-read on every run, so a corrected publication replaces the
  # stored figure.
  REFRESH_MONTHS = 3

  def initialize(provider: Provider::Ecb.new)
    @provider = provider
  end

  def self.enabled?
    ExternalAccess.enabled?(:reference_rates)
  end

  # Imports every known index. Returns { index_key => rows stored }.
  def import_all!
    ReferenceRate::INDEXES.keys.index_with { |index_key| import!(index_key) }
  end

  def import!(index_key)
    response = @provider.monthly_series(index_key, start_month: start_month_for(index_key))

    unless response.success?
      DebugLogEntry.capture(
        category: "reference_rates", level: "warn", message: response.error&.message.to_s,
        source: self.class.name, provider_key: "ecb", metadata: { index_key: index_key }
      )
      return 0
    end

    ReferenceRate.store!(index_key: index_key, observations: response.data, source: "ecb")
  end

  private
    # Recent months are re-read every run. A loan whose variable period
    # started before the stored series also needs everything from the month
    # before its first revision, however long ago.
    def start_month_for(index_key)
      series = ReferenceRate.for_index(index_key)
      latest = series.maximum(:month)
      needed = Loan::RatePeriod.where(reference_index: index_key).minimum(:starts_on)&.beginning_of_month&.prev_month
      earliest = series.minimum(:month)

      return [ needed, Date.current.beginning_of_month << INITIAL_HISTORY_MONTHS ].compact.min if latest.nil?
      return needed if needed && earliest && needed < earliest

      latest << REFRESH_MONTHS
    end
end
