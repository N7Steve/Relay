require "test_helper"

class SyncAllProvidersJobTest < ActiveJob::TestCase
  test "provider-wide sync continues after refresh orchestration" do
    family = families(:dylan_family)

    Family.stubs(:find_by).with(id: family.id).returns(family)
    PlaidTransactionsRefreshAllJob.stubs(:perform_later).raises(RedisClient::Error, "Redis unavailable")
    family.expects(:sync_later)

    SyncAllProvidersJob.perform_now(family.id)
  end

  test "provider-wide sync ignores a deleted family" do
    Family.expects(:find_by).returns(nil)

    Family.any_instance.expects(:request_plaid_transactions_refreshes_later).never

    SyncAllProvidersJob.perform_now("missing")
  end
end
