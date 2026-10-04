require "test_helper"

class OnboardableTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:empty)
  end

  test "must complete onboarding before any other action" do
    @user.update!(onboarded_at: nil)

    get root_path
    assert_redirected_to onboarding_path
  end

  test "onboarded users can visit dashboard without a subscription" do
    @user.update!(onboarded_at: 1.day.ago)
    @user.family.subscription&.destroy!

    get root_path
    assert_response :success
  end

  test "expired historical trial does not block dashboard access or mutate billing" do
    @user.update!(onboarded_at: 1.day.ago)
    @user.family.subscription&.destroy!
    subscription = @user.family.create_subscription!(status: :trialing, trial_ends_at: 90.days.ago)

    get root_path
    assert_response :success
    assert_equal "trialing", subscription.reload.status
    assert_select "a[href='/subscription/upgrade']", count: 0
  end
end
