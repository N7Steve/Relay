require "test_helper"

class ExternalScheduleTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Cron::Job.stubs(:find).with("clean_inactive_families").returns(nil)
    Sidekiq::Cron::Job.stubs(:find).with("sync_hourly").returns(nil)
  end

  test "removes retired commercial cron without touching shared queues or other schedules" do
    schedule = {
      "clean_inactive_families" => { "class" => "InactiveFamilyCleanerJob" },
      "clean_syncs" => { "class" => "SyncCleanerJob" }
    }
    stale_job = mock("persisted commercial cron")
    stale_job.expects(:destroy).once
    Sidekiq::Cron::Job.expects(:find).with("clean_inactive_families").returns(stale_job)
    Sidekiq::Cron::Job.expects(:load_from_hash).with(schedule.except("clean_inactive_families"))

    ExternalSchedule.reconcile!(schedule)
  end
  test "reconciliation deletes only disabled owned jobs and retains local maintenance" do
    schedule = {
      "import_market_data" => { "class" => "ImportMarketDataJob" },
      "clean_syncs" => { "class" => "SyncCleanerJob" },
      "generate_scheduled_payments" => { "class" => "GenerateScheduledPaymentsJob" },
      "dispatch_google_drive_exports" => { "class" => "DispatchGoogleDriveExportsJob" }
    }
    Setting.stubs(:external_market_data_enabled).returns(false)
    stale_job = mock("persisted market cron")
    stale_job.expects(:destroy).once
    Sidekiq::Cron::Job.expects(:find).with("import_market_data").returns(stale_job)
    Sidekiq::Cron::Job.expects(:load_from_hash).with(schedule.except("import_market_data"))
    ExternalSchedule.reconcile!(schedule)

    Sidekiq::Cron::Job.expects(:find).with("import_market_data").returns(nil)
    Sidekiq::Cron::Job.expects(:load_from_hash).with(schedule.except("import_market_data"))
    ExternalSchedule.reconcile!(schedule)
  end
end
