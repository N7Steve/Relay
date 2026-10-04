require "test_helper"

class StripeEventHandlerJobTest < ActiveJob::TestCase
  test "already queued webhook events never contact Stripe or mutate billing" do
    Provider::Registry.expects(:get_provider).with(:stripe).never
    before = Subscription.order(:id).map(&:attributes)

    StripeEventHandlerJob.perform_now("evt_legacy")

    assert_equal before, Subscription.order(:id).map(&:attributes)
  end
end
