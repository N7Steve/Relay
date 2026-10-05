require "test_helper"

class ExternalScheduleTest < ActiveSupport::TestCase
  test "reconciliation deletes only disabled owned jobs and retains local maintenance" do
    schedule = {
      "sync_property_valuations" => { "class" => "SyncPropertyValuationsJob" },
      "clean_syncs" => { "class" => "SyncCleanerJob" },
      "generate_scheduled_payments" => { "class" => "GenerateScheduledPaymentsJob" },
      "dispatch_google_drive_exports" => { "class" => "DispatchGoogleDriveExportsJob" }
    }
    Setting.stubs(:external_property_valuations_enabled).returns(false)
    stale_job = mock("persisted property valuation cron")
    stale_job.expects(:destroy).once
    Sidekiq::Cron::Job.expects(:find).with("sync_property_valuations").returns(stale_job)
    Sidekiq::Cron::Job.expects(:load_from_hash).with(schedule.except("sync_property_valuations"))
    ExternalSchedule.reconcile!(schedule)

    Sidekiq::Cron::Job.expects(:find).with("sync_property_valuations").returns(nil)
    Sidekiq::Cron::Job.expects(:load_from_hash).with(schedule.except("sync_property_valuations"))
    ExternalSchedule.reconcile!(schedule)
  end
end
