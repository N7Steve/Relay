require "test_helper"

class ExternalAccessJobTest < ActiveJob::TestCase
  test "previously queued remote jobs are consumed without dispatch or network" do
    Setting.stubs(:external_bank_sync_enabled).returns(false)
    Family.expects(:find_each).never
    SyncAllJob.perform_now

    Setting.stubs(:external_google_drive_enabled).returns(false)
    GoogleDriveExportSchedule.expects(:due).never
    DispatchGoogleDriveExportsJob.perform_now
  end

  test "queued connector sync is cancelled and keeps historical data" do
    Setting.stubs(:external_bank_sync_enabled).returns(false)
    item = enable_banking_items(:one)
    sync = item.syncs.create!
    item.expects(:perform_sync).never
    sync.perform
    assert sync.reload.stale?
    assert item.reload.persisted?
  end
end
