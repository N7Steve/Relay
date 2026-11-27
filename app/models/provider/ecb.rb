require "csv"

# The European Central Bank's statistical data API: monthly averages of the
# Euribor fixings, the same figures the Bank of Spain publishes (to three
# decimals) as the official reference for Spanish variable mortgages.
#
# Public and keyless. Requests need the installation's `reference_rates`
# external capability; the check runs on the transport too, so a client built
# before the capability was switched off cannot reach the network after.
class Provider::Ecb < Provider
  Error = Class.new(Provider::Error)

  BASE_URL = "https://data-api.ecb.europa.eu".freeze
  SERIES = {
    "euribor_12m" => "FM/M.U2.EUR.RT.MM.EURIBOR1YD_.HSTA"
  }.freeze

  # Monthly values for `index_key` from `start_month` onwards, as
  # { Date (first of month) => BigDecimal }.
  def monthly_series(index_key, start_month:)
    with_provider_response do
      series = SERIES.fetch(index_key) { raise Error.new("Unsupported index #{index_key}") }
      response = connection.get("/service/data/#{series}") do |request|
        request.params["format"] = "csvdata"
        request.params["detail"] = "dataonly"
        request.params["startPeriod"] = start_month.strftime("%Y-%m")
      end

      parse_csv(response.body)
    end
  end

  private
    def require_external_access!
      ExternalAccess.require!(:reference_rates)
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |faraday|
        faraday.use ExternalAccess::RequestMiddleware, :reference_rates
        faraday.options.open_timeout = 10
        faraday.options.timeout = 20
        faraday.headers["Accept"] = "text/csv"
        faraday.response :raise_error
      end
    end

    def parse_csv(body)
      CSV.parse(body.to_s, headers: true).each_with_object({}) do |row, values|
        period = row["TIME_PERIOD"]
        value = row["OBS_VALUE"]
        next if period.blank? || value.blank?

        month = Date.strptime(period, "%Y-%m")
        values[month] = BigDecimal(value)
      end
    rescue CSV::MalformedCSVError, Date::Error, ArgumentError => error
      raise Error.new("Unreadable ECB response: #{error.message}")
    end
end
