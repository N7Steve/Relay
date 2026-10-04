require "test_helper"

class SyncAllJobTest < ActiveJob::TestCase
  test "scheduled sync continues after refresh orchestration" do
    family = families(:dylan_family)
    Family.stubs(:find_each).yields(family)
    PlaidTransactionsRefreshAllJob.stubs(:perform_later).raises(RedisClient::Error, "Redis unavailable")
    family.expects(:sync_later)

    SyncAllJob.perform_now
  end
end
