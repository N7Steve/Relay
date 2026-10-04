require "test_helper"

class SelfHostedRetirementTest < ActionDispatch::IntegrationTest
  test "commercial routes are absent even with legacy mode flags" do
    ClimateControl.modify(SELF_HOSTED: "false", SELF_HOSTING_ENABLED: "false") do
      [ [ :get, "/subscription" ], [ :get, "/subscription/new" ],
        [ :post, "/subscription" ], [ :get, "/subscription/upgrade" ],
        [ :get, "/subscription/success" ], [ :get, "/settings/payment" ],
        [ :get, "/onboarding/trial" ], [ :post, "/webhooks/stripe" ] ].each do |method, path|
        assert_raises(ActionController::RoutingError) do
          Rails.application.routes.recognize_path(path, method: method)
        end
      end
      assert_raises(Provider::Registry::Error) { Provider::Registry.get_provider(:stripe) }
      assert_not Apns::Client.hosted?
    end
  end

  test "instance administration ignores old commercial filters and shows role controls" do
    sign_in users(:sure_support_staff)

    get admin_users_url, params: { trial_status: "expiring_soon" }

    assert_response :success
    assert_select "select[name='trial_status']", count: 0
    assert_includes response.body, users(:family_admin).email
    assert_includes response.body, "Super Admin"
    assert_select "a[href='/settings/payment']", count: 0
  end
end
