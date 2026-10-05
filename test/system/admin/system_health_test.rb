require "application_system_test_case"

class Admin::SystemHealthTest < ApplicationSystemTestCase
  setup do
    sign_in users(:sure_support_staff)
    stub_healthy_sidekiq
  end

  test "super admin sees Sidekiq status without push notification controls" do
    visit admin_system_health_path(tab: "background_jobs")

    assert_selector "h2", text: "Sidekiq status"
    assert_no_text "Push notifications"
  end

  private
    def stub_healthy_sidekiq
      SidekiqHealth.any_instance.stubs(:healthy?).returns(true)
      SidekiqHealth.any_instance.stubs(:processes_count).returns(1)
      SidekiqHealth.any_instance.stubs(:last_heartbeat_at).returns(Time.current)
      SidekiqHealth.any_instance.stubs(:max_queue_latency).returns(0.0)
      SidekiqHealth.any_instance.stubs(:enqueued_count).returns(0)
      SidekiqHealth.any_instance.stubs(:retry_count).returns(0)
      SidekiqHealth.any_instance.stubs(:failed_count).returns(0)
      SidekiqHealth.any_instance.stubs(:processed_count).returns(42)
      SidekiqHealth.any_instance.stubs(:queue_breakdown).returns([ [ "default", 0, 0.0 ] ])
    end
end
