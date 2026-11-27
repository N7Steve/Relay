require "test_helper"

class ReferenceRate::ImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  ECB_URL = %r{\Ahttps://data-api\.ecb\.europa\.eu/service/data/FM/M\.U2\.EUR\.RT\.MM\.EURIBOR1YD_\.HSTA}

  setup do
    ReferenceRate.delete_all
  end

  test "stores the monthly Euribor from the ECB, replacing a corrected month" do
    Setting.stubs(:external_reference_rates_enabled).returns(true)
    ReferenceRate.create!(index_key: "euribor_12m", month: Date.new(2026, 9, 1), value: 3.2, source: "ecb")
    stub_request(:get, ECB_URL).to_return(status: 200, body: <<~CSV)
      KEY,FREQ,REF_AREA,CURRENCY,PROVIDER_FM,INSTRUMENT_FM,PROVIDER_FM_ID,DATA_TYPE_FM,TIME_PERIOD,OBS_VALUE
      FM.M.U2.EUR.RT.MM.EURIBOR1YD_.HSTA,M,U2,EUR,RT,MM,EURIBOR1YD_,HSTA,2026-09,3.247
      FM.M.U2.EUR.RT.MM.EURIBOR1YD_.HSTA,M,U2,EUR,RT,MM,EURIBOR1YD_,HSTA,2026-10,3.2385909
    CSV

    assert_equal 2, ReferenceRate::Importer.new.import!("euribor_12m")

    assert_equal BigDecimal("3.247"), ReferenceRate.find_by!(month: Date.new(2026, 9, 1)).value
    october = ReferenceRate.find_by!(month: Date.new(2026, 10, 1))
    assert_equal BigDecimal("3.23859"), october.value
    assert_equal BigDecimal("3.239"), october.published_value
  end

  test "a failed download is logged and stores nothing" do
    Setting.stubs(:external_reference_rates_enabled).returns(true)
    stub_request(:get, ECB_URL).to_return(status: 503, body: "unavailable")

    assert_difference -> { DebugLogEntry.where(category: "reference_rates").count }, 1 do
      assert_equal 0, ReferenceRate::Importer.new.import!("euribor_12m")
    end
    assert_equal 0, ReferenceRate.count
  end

  test "nothing leaves the installation unless reference rates are enabled" do
    Setting.stubs(:external_reference_rates_enabled).returns(false)

    assert_not ReferenceRate::Importer.enabled?
    response = Provider::Ecb.new.monthly_series("euribor_12m", start_month: Date.new(2026, 1, 1))
    assert_not response.success?
    assert_not_requested :get, ECB_URL
  end

  test "the daily job imports only when enabled and always reviews loans" do
    Setting.stubs(:external_reference_rates_enabled).returns(false)
    ReferenceRate::Importer.any_instance.expects(:import_all!).never

    assert_enqueued_with(job: ReviewLoanRatesJob) { ImportReferenceRatesJob.perform_now }
  end
end
