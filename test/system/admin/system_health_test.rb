require "application_system_test_case"

class Admin::SystemHealthTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    sign_in users(:sure_support_staff)
    stub_healthy_sidekiq
  end

  test "hosted super admin enables the test button by registering an iOS device" do
    Apns::Client.stubs(:hosted?).returns(true)
    Apns::Client.stubs(:configured?).returns(true)
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    visit admin_system_health_path
    assert_selector "button[role='tab']", count: 1
    assert_selector "button[role='tab'][aria-selected='true']", text: "Background jobs"
    assert_selector "h2", text: "Push notifications"
    assert_button "Send test push notification", disabled: true
    assert_text "Enable push notifications in the Relay iOS app"

    user = users(:sure_support_staff)
    user.push_subscriptions.create!(
      token: "ab" * 32, environment: "sandbox", platform: "ios", last_registered_at: Time.current
    )
    visit admin_system_health_path(tab: "background_jobs")
    assert_button "Send test push notification", disabled: false
    Apns::Client.expects(:new).never
    assert_enqueued_jobs 1, only: DeliverTestPushNotificationJob do
      click_button "Send test push notification"
      assert_text "Test notification queued"
    end
    assert_text "Queued"
    assert_button "Send test push notification", disabled: true
    Apns::Client.unstub(:new)
    Apns::Client.any_instance.stubs(:deliver_test).returns(stub(ok?: true))
    perform_enqueued_jobs only: DeliverTestPushNotificationJob
    travel 31.seconds do
      visit admin_system_health_path(tab: "background_jobs")
      assert_text "Latest test requested at"
      assert_text "Accepted by APNs"
      assert_button "Send test push notification", disabled: false
      page.save_screenshot(Rails.root.join("tmp", "system-health-background-push-notifications.png"))
    end
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
