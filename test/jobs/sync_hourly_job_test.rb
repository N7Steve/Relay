require "test_helper"

class SyncHourlyJobTest < ActiveJob::TestCase
  test "a queued retired hourly job leaves historical records and queues unchanged" do
    item = enable_banking_items(:one)
    before = item.attributes
    assert_no_enqueued_jobs { SyncHourlyJob.perform_now }
    assert_equal before, item.reload.attributes
  end
end
