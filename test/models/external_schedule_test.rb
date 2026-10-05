require "test_helper"

class ExternalScheduleTest < ActiveSupport::TestCase
  setup do
    ExternalSchedule::RETIRED_JOBS.each { |name| Sidekiq::Cron::Job.stubs(:find).with(name).returns(nil) }
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
  test "removes persisted Bills cron and keeps Agenda on repeated reconciliation" do
    schedule = {
      "generate_recurring_occurrences" => { "class" => "GenerateRecurringOccurrencesJob" },
      "generate_scheduled_payments" => { "class" => "GenerateScheduledPaymentsJob" }
    }
    stale_job = mock("persisted Bills cron")
    stale_job.expects(:destroy).once
    Sidekiq::Cron::Job.expects(:find).with("generate_recurring_occurrences").returns(stale_job)
    Sidekiq::Cron::Job.expects(:load_from_hash).with(schedule.except("generate_recurring_occurrences")).twice

    ExternalSchedule.reconcile!(schedule)
    ExternalSchedule.reconcile!(schedule)
  end

  test "removes persisted FinanceKit cron even when bank access is enabled" do
    schedule = {
      "process_financekit_inbox" => { "class" => "FinancekitInboxJob" },
      "clean_syncs" => { "class" => "SyncCleanerJob" }
    }
    ExternalAccess.stubs(:enabled?).returns(true)
    stale_job = mock("persisted FinanceKit cron")
    stale_job.expects(:destroy).once
    Sidekiq::Cron::Job.expects(:find).with("process_financekit_inbox").returns(stale_job)
    Sidekiq::Cron::Job.expects(:load_from_hash).with(schedule.except("process_financekit_inbox"))

    ExternalSchedule.reconcile!(schedule)
  end

  test "removes persisted market data cron without a capability to re-enable it" do
    schedule = {
      "import_market_data" => { "class" => "ImportMarketDataJob" },
      "run_security_health_checks" => { "class" => "SecurityHealthCheckJob" },
      "clean_syncs" => { "class" => "SyncCleanerJob" }
    }
    %w[import_market_data run_security_health_checks].each do |name|
      stale_job = mock("persisted #{name} cron")
      stale_job.expects(:destroy).once
      Sidekiq::Cron::Job.expects(:find).with(name).returns(stale_job)
    end
    Sidekiq::Cron::Job.expects(:load_from_hash).with(schedule.slice("clean_syncs"))

    ExternalSchedule.reconcile!(schedule)
  end

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
