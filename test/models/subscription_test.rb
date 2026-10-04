require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  test "family sync never expires a historical trial" do
    subscription = subscriptions(:expired_trial)
    subscription.update!(status: :trialing, trial_ends_at: 90.days.ago)
    before = subscription.attributes
    ExternalAccess.stubs(:enabled?).with(:bank_sync).returns(false)
    sync = subscription.family.syncs.create!(status: :syncing)

    Family::Syncer.new(subscription.family).perform_sync(sync)

    assert_equal before, subscription.reload.attributes
  end

  test "historical billing remains readable without commercial operations" do
    subscription = subscriptions(:active)

    assert subscription.active?
    assert_equal "test_1234567890", subscription.stripe_id
    assert_equal subscription, subscription.family.subscription
    assert_not subscription.respond_to?(:pending_cancellation?)
    assert_not subscription.family.respond_to?(:start_subscription!)
    assert_not subscription.family.respond_to?(:sync_trial_status!)
  end
end
