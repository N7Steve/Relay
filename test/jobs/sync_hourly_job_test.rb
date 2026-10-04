require "test_helper"

class SyncHourlyJobTest < ActiveJob::TestCase
  test "a queued retired hourly job leaves historical records and queues unchanged" do
    item = CoinstatsItem.create!(family: families(:dylan_family), name: "Historical Coinstats", api_key: "obsolete")
    before = item.attributes
    assert_no_enqueued_jobs { SyncHourlyJob.perform_now }
    assert_equal before, item.reload.attributes
  end
end
