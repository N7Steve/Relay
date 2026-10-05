require "test_helper"

class SyncAllJobTest < ActiveJob::TestCase
  test "scheduled sync continues after a family fails" do
    failing = families(:dylan_family)
    family = families(:empty)
    Family.stubs(:find_each).multiple_yields([ failing ], [ family ])
    failing.expects(:sync_later).raises(RedisClient::Error, "Redis unavailable")
    family.expects(:sync_later)

    SyncAllJob.perform_now
  end
end
