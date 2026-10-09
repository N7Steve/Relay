# SQL aggregate conversion must detect missing data in the same scope as its
# amounts. NULL multiplication alone would silently produce partial totals.
class FinancialConversion
  def self.rate_sql(currency:, target: ":target_currency", rate: "er.rate")
    "CASE WHEN #{currency} = #{target} THEN 1 ELSE #{rate} END"
  end

  def self.missing_sql(currency:, date:, target: ":target_currency", rate: "er.rate", condition: "TRUE")
    "MIN(CASE WHEN (#{condition}) AND #{currency} != #{target} AND #{rate} IS NULL THEN #{currency} || '/' || (#{date})::date::text END)"
  end

  def self.validate!(rows, to:)
    missing = rows.find { |row| row["missing_rate"].present? }
    return unless missing

    from, date = missing["missing_rate"].split("/", 2)
    raise Money::ConversionError.new(from_currency: from, to_currency: to, date: Date.iso8601(date))
  end
end
