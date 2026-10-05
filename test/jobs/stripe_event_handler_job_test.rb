require "test_helper"

class StripeEventHandlerJobTest < ActiveJob::TestCase
  test "already queued webhook events never contact Stripe or mutate billing" do
    Provider::Registry.expects(:get_provider).with(:stripe).never
    before = Family.order(:id).map(&:attributes)

    StripeEventHandlerJob.perform_now("evt_legacy")

    assert_equal before, Family.order(:id).map(&:attributes)
  end
end
