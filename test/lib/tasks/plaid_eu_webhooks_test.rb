require "test_helper"

class PlaidEuWebhooksTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("data_migration:eu_plaid_webhooks")
    @task = Rake::Task["data_migration:eu_plaid_webhooks"]
    @task.reenable
  end

  test "missing destination refuses to load provider configuration or update items" do
    Provider::PlaidEuAdapter.expects(:ensure_configuration_loaded).never
    with_env_overrides("PLAID_EU_WEBHOOK_URL" => nil) do
      assert_raises(KeyError) { @task.invoke }
    end
  end

  test "invalid destinations refuse provider calls" do
    Provider::PlaidEuAdapter.expects(:ensure_configuration_loaded).never
    [ "", "http://relay.example.test/webhooks/plaid_eu", "https://user:pass@relay.example.test/webhooks/plaid_eu", "https://relay.example.test/#fragment" ].each do |url|
      @task.reenable
      with_env_overrides("PLAID_EU_WEBHOOK_URL" => url) do
        assert_raises(ArgumentError) { @task.invoke }
      end
    end
  end

  test "updates only EU items using the explicit installation destination" do
    item = plaid_items(:one)
    item.update!(plaid_region: "eu")
    other = PlaidItem.create!(family: item.family, plaid_id: "non-eu-item", access_token: "test-token", name: "Non EU", plaid_region: "us")
    url = "https://relay.example.test/webhooks/plaid_eu"
    Provider::PlaidEuAdapter.stubs(:ensure_configuration_loaded)
    client = mock
    client.expects(:item_webhook_update).once.with do |request|
      request.webhook == url && request.access_token == item.access_token
    end
    Provider::Plaid.stubs(:new).returns(stub(client: client))

    with_env_overrides("PLAID_EU_WEBHOOK_URL" => url) do
      capture_io { @task.invoke }
    end
    assert_equal "us", other.reload.plaid_region
  end
end
