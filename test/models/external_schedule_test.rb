require "test_helper"

class ExternalScheduleTest < ActiveSupport::TestCase
  test "reconciliation removes persisted phase 12 schedules and keeps local maintenance" do
    schedule = {
      "refresh_demo_family" => { "class" => "DemoFamilyRefreshJob" },
      "clean_syncs" => { "class" => "SyncCleanerJob" },
      "generate_scheduled_payments" => { "class" => "GenerateScheduledPaymentsJob" }
    }
    demo_job = mock("persisted demo cron")
    demo_job.expects(:destroy).once
    Sidekiq::Cron::Job.expects(:find).with("refresh_demo_family").returns(demo_job)
    Sidekiq::Cron::Job.expects(:find).with("sync_property_valuations").returns(nil)
    Sidekiq::Cron::Job.expects(:load_from_hash).with(schedule.except("refresh_demo_family"))

    ExternalSchedule.reconcile!(schedule)
  end

  test "reconciliation deletes only disabled owned jobs and retains local maintenance" do
    schedule = {
      "clean_syncs" => { "class" => "SyncCleanerJob" },
      "generate_scheduled_payments" => { "class" => "GenerateScheduledPaymentsJob" },
      "dispatch_google_drive_exports" => { "class" => "DispatchGoogleDriveExportsJob" }
    }
    Setting.stubs(:external_google_drive_enabled).returns(false)
    ExternalSchedule::RETIRED_JOBS.each { |name| Sidekiq::Cron::Job.stubs(:find).with(name).returns(nil) }
    stale_job = mock("persisted Google Drive cron")
    stale_job.expects(:destroy).once
    Sidekiq::Cron::Job.expects(:find).with("dispatch_google_drive_exports").returns(stale_job)
    Sidekiq::Cron::Job.expects(:load_from_hash).with(schedule.except("dispatch_google_drive_exports"))

    ExternalSchedule.reconcile!(schedule)
  end
end
