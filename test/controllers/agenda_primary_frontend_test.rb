require "test_helper"

class AgendaPrimaryFrontendTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "retired Bills routes cannot read or mutate historical data" do
    id = recurring_transactions(:netflix_subscription).id
    requests = [
      [ :get, "/bills" ], [ :get, "/bills/#{id}" ],
      [ :post, "/bills/detect" ], [ :post, "/bills/reset_feed_token" ],
      [ :get, "/bills_feed/old-token.ics" ],
      [ :get, "/recurring_transactions" ], [ :post, "/recurring_transactions" ],
      [ :patch, "/recurring_transactions/#{id}" ], [ :delete, "/recurring_transactions/#{id}" ],
      [ :post, "/recurring_transactions/identify" ], [ :post, "/recurring_transactions/cleanup" ],
      [ :patch, "/recurring_transactions/update_settings" ],
      [ :get, "/recurring_occurrences/#{id}" ], [ :post, "/recurring_occurrences/#{id}/mark_paid" ],
      [ :post, "/recurring_occurrences/#{id}/allocations" ],
      [ :post, "/recurring_allocations/#{id}/confirm" ], [ :delete, "/recurring_allocations/#{id}" ],
      [ :post, "/transactions/#{entries(:transaction).transaction.id}/mark_as_recurring" ],
      [ :post, "/transfers/#{transfers(:one).id}/mark_as_recurring" ]
    ]

    assert_no_difference [ "RecurringTransaction.count", "RecurringOccurrence.count", "RecurringAllocation.count", "ScheduledPayment.count" ] do
      requests.each do |verb, path|
        public_send(verb, path)
        assert_response :not_found
      end
    end
  end

  test "settings and transactions expose Agenda without Bills actions" do
    get settings_preferences_url
    assert_response :success
    assert_select "a[href='/recurring_transactions']", count: 0

    get transactions_url
    assert_response :success
    assert_select "[data-tab-id=upcoming]", count: 0

    entry = entries(:transaction)
    get transaction_url(entry)
    assert_response :success
    assert_select "a[href=?]", new_scheduled_payment_path(from_entry_id: entry.id), count: 1
    assert_select "a[href*='recurring_transactions'], a[href*='mark_as_recurring']", count: 0
  end

  test "transfer details offer Agenda" do
    transfer = transfers(:one)
    get transfer_url(transfer)

    assert_response :success
    assert_select "a[href=?]", new_scheduled_payment_path(from_entry_id: transfer.outflow_transaction.entry.id), count: 1
    assert_select "a[href*='mark_as_recurring']", count: 0
  end

  test "historical Bills insights stay out of the frontend with preview enabled" do
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => true))
    get insights_url

    assert_response :success
    assert_no_match CGI.escapeHTML(insights(:cash_flow_warning).title), response.body
  end
end
