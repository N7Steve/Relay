require "test_helper"

class DeliverInsightNotificationJobTest < ActiveJob::TestCase
  setup do
    Apns::Client.stubs(:hosted?).returns(true)
    Apns::Client.stubs(:configured?).returns(true)
    @insight = insights(:spending_anomaly_dining)
    @insight.update!(priority: "high")
    user = @insight.family.users.first
    user.update!(preferences: user.preferences.merge("preview_features_enabled" => true))
    @subscription = user.push_subscriptions.create!(
      token: "ab" * 32,
      environment: "sandbox",
      platform: "ios",
      last_registered_at: Time.current
    )
  end

  test "historical Bills insights cannot enqueue notifications or execute old delivery jobs" do
    historical = insights(:cash_flow_warning)
    Apns::Client.expects(:new).never

    %w[cash_flow_warning subscription_audit].each do |type|
      historical.update!(insight_type: type)
      job = DeliverInsightNotificationJob.new(insight_id: historical.id, push_subscription_id: @subscription.id)
      assert_no_enqueued_jobs only: DeliverInsightNotificationJob do
        DeliverInsightNotificationJob.enqueue_for(historical)
        ActiveJob::Base.execute(job.serialize)
      end
    end
  end

  test "a job queued before a device changed users cannot reach its replacement" do
    @subscription.update!(device_key_digest: Digest::SHA256.hexdigest("cd" * 32))
    old_id = @subscription.id
    next_user = @insight.family.users.where.not(id: @subscription.user_id).first!
    replacement = PushSubscription.register_for!(user: next_user, token: @subscription.token,
      environment: "sandbox", platform: "ios", device_key: "cd" * 32)
    Apns::Client.expects(:new).never
    DeliverInsightNotificationJob.perform_now(insight_id: @insight.id, push_subscription_id: old_id)
    assert PushSubscription.exists?(replacement.id)
    assert_not PushSubscription.exists?(old_id)
  end

  test "delivers a privacy-preserving insight notification" do
    response = stub(ok?: true)
    client = mock
    Apns::Client.expects(:new).with(environment: "sandbox").returns(client)
    client.expects(:deliver).with(
      token: @subscription.token,
      title: "New financial insight",
      body: "Open Relay to review your latest AI insight.",
      insight_id: @insight.id
    ).returns(response)

    DeliverInsightNotificationJob.perform_now(
      insight_id: @insight.id,
      push_subscription_id: @subscription.id
    )
  end

  test "localizes notifications using the family locale" do
    @insight.family.update!(locale: "de")
    response = stub(ok?: true)
    client = mock
    Apns::Client.stubs(:new).returns(client)
    client.expects(:deliver).with(
      token: @subscription.token,
      title: "Neue Finanzanalyse",
      body: "Öffne Relay, um deine neueste KI-Analyse anzusehen.",
      insight_id: @insight.id
    ).returns(response)

    DeliverInsightNotificationJob.perform_now(
      insight_id: @insight.id,
      push_subscription_id: @subscription.id
    )
  end

  test "removes tokens rejected as unregistered" do
    response = stub(ok?: false, status: "410", body: { "reason" => "Unregistered" })
    Apns::Client.any_instance.stubs(:deliver).returns(response)

    assert_difference "PushSubscription.count", -1 do
      DeliverInsightNotificationJob.perform_now(
        insight_id: @insight.id,
        push_subscription_id: @subscription.id
      )
    end
  end

  test "does not send an insight to a device from another family" do
    other_subscription = users(:empty).push_subscriptions.create!(
      token: "cd" * 32,
      environment: "sandbox",
      platform: "ios",
      last_registered_at: Time.current
    )
    Apns::Client.expects(:new).never

    DeliverInsightNotificationJob.perform_now(
      insight_id: @insight.id,
      push_subscription_id: other_subscription.id
    )
  end

  test "self hosted mode prevents enqueueing and execution of old jobs" do
    Apns::Client.stubs(:hosted?).returns(false)
    Apns::Client.expects(:new).never
    assert_no_enqueued_jobs do
      DeliverInsightNotificationJob.enqueue_for(@insight)
      DeliverInsightNotificationJob.perform_now(insight_id: @insight.id, push_subscription_id: @subscription.id)
    end
  end

  test "preview opt out after enqueueing prevents delivery" do
    @subscription.user.update!(preferences: { "preview_features_enabled" => false })
    Apns::Client.expects(:new).never
    DeliverInsightNotificationJob.perform_now(insight_id: @insight.id, push_subscription_id: @subscription.id)
  end

  test "stale registrations and inactive users cannot receive insight pushes" do
    @subscription.update!(last_registered_at: 91.days.ago)
    Apns::Client.expects(:new).never
    DeliverInsightNotificationJob.perform_now(insight_id: @insight.id, push_subscription_id: @subscription.id)
    @subscription.update!(last_registered_at: Time.current)
    @subscription.user.update_column(:active, false)
    DeliverInsightNotificationJob.perform_now(insight_id: @insight.id, push_subscription_id: @subscription.id)
  end

  test "low priority and already read insights cannot enqueue or deliver" do
    Apns::Client.expects(:new).never
    [ { priority: "low" }, { priority: "high", status: "read" }, { status: "expired" }, { status: "acknowledged" } ].each do |attributes|
      @insight.update!(attributes)
      assert_no_enqueued_jobs do
        DeliverInsightNotificationJob.enqueue_for(@insight)
        DeliverInsightNotificationJob.perform_now(insight_id: @insight.id, push_subscription_id: @subscription.id)
      end
    end
  end
end
