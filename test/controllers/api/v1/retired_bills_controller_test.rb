require "test_helper"

class Api::V1::RetiredBillsControllerTest < ActionDispatch::IntegrationTest
  test "Bills API is unavailable even with a valid write key" do
    user = users(:family_admin)
    user.api_keys.active.destroy_all
    key = ApiKey.create!(user: user, name: "Retired Bills test", scopes: [ "read_write" ], display_key: "test_#{SecureRandom.hex(8)}")
    headers = api_headers(key)
    id = recurring_transactions(:netflix_subscription).id

    assert_no_difference [ "RecurringTransaction.count", "RecurringOccurrence.count", "ScheduledPayment.count" ] do
      [ [ :get, "" ], [ :get, "/#{id}" ], [ :post, "" ], [ :patch, "/#{id}" ], [ :delete, "/#{id}" ] ].each do |verb, suffix|
        public_send(verb, "/api/v1/recurring_transactions#{suffix}", headers: headers)
        assert_response :not_found
      end
    end
  end

  private
    def api_headers(api_key)
      { "X-Api-Key" => api_key.display_key }
    end
end
