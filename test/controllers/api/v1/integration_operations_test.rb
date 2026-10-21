# frozen_string_literal: true

require "test_helper"

class Api::V1::IntegrationOperationsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @key = ApiKey.create!(user: @user, name: "Integrations", scopes: %w[read_write], source: "web", display_key: "integration_#{SecureRandom.hex(12)}")
  end

  test "local recalculation enqueues one sync replays and pending cancellation uses native states" do
    account = accounts(:depository)
    account.syncs.destroy_all
    args = { account_id: account.id, idempotency_key: "recalculate" }
    assert_enqueued_with(job: ApiIntegrationJob) do
      invoke("recalculate_account", args)
      assert_response :success, response.body
    end
    id = response.parsed_body.fetch("id")
    assert_no_difference "Sync.count" do
      invoke("recalculate_account", args)
      assert_response :success
    end
    invoke("get_sync", sync_id: id)
    assert_response :success
    invoke("cancel_sync", sync_id: id, idempotency_key: "cancel")
    assert_response :success, response.body
    assert Sync.find(id).stale?
  end

  test "bank status excludes credentials and binding preserves cached account values" do
    item = enable_banking_items(:one)
    source = item.enable_banking_accounts.create!(uid: SecureRandom.uuid, name: "Selected savings", currency: "EUR", current_balance: "42")
    invoke("get_bank_connection", bank_item_id: item.id)
    assert_response :success
    refute_match(/test-certificate|test-session|test-app/, response.body)
    invoke("setup_bank_account", bank_item_id: item.id, bank_account_id: source.id, accountable_type: "Depository", subtype: "savings", idempotency_key: "setup")
    assert_response :success, response.body
    record = Account.find(response.parsed_body.fetch("id"))
    assert_equal @user, record.owner
    assert_equal 42.to_d, record.balance
    assert_equal source, record.account_providers.first.provider
    invoke("list_bank_accounts", bank_item_id: item.id)
    assert_response :success
    invoke("get_human_flow", flow: "bank_authorization", bank_item_id: item.id)
    assert_response :success
    assert response.parsed_body.fetch("human_required")
    assert_not response.body.include?("test-certificate")
  end

  test "bank syncing respects suspension and cannot leak a private member account" do
    previous = ENV["RELAY_EXTERNAL_BANK_SYNC_ENABLED"]
    ENV["RELAY_EXTERNAL_BANK_SYNC_ENABLED"] = "false"
    invoke("sync_bank", bank_item_id: enable_banking_items(:one).id, idempotency_key: "disabled-bank")
    assert_response :unprocessable_entity
    accounts(:investment).update!(owner: users(:family_member))
    accounts(:investment).account_shares.where(user: @user).destroy_all
    invoke("list_bank_connections", {})
    assert_response :forbidden
  ensure
    ENV["RELAY_EXTERNAL_BANK_SYNC_ENABLED"] = previous
  end

  test "Drive schedules use only the actor connection and authorized accounts" do
    connection = @user.create_google_drive_connection!(family: @user.family, google_subject: "subject", email: "drive@example.com", refresh_token: "PRIVATE_REFRESH", access_token: "PRIVATE_ACCESS", connected_at: Time.current)
    invoke("get_drive_connection", {})
    assert_response :success
    refute_match(/PRIVATE_/, response.body)
    invoke("create_drive_schedule", name: "Monthly CSV", filename: "monthly.csv", frequency: "monthly", day_of_month: 2, run_at: "06:00", timezone: "Europe/Madrid", filters: { account_ids: [ accounts(:depository).id ] }, idempotency_key: "drive-schedule")
    assert_response :success, response.body
    id = response.parsed_body.fetch("id")
    assert_equal connection, GoogleDriveExportSchedule.find(id).google_drive_connection
    invoke("update_drive_schedule", schedule_id: id, status: "paused", idempotency_key: "pause-drive")
    assert_response :success, response.body
    invoke("list_drive_runs", schedule_id: id)
    assert_response :success
    @key.update!(user: users(:family_member))
    invoke("get_drive_schedule", schedule_id: id)
    assert_response :not_found
    @key.update!(user: @user)
    invoke("delete_drive_schedule", schedule_id: id, idempotency_key: "delete-drive")
    assert_response :success
  end

  private
    def invoke(name, args)
      post "/api/v1/actions/#{name}", params: { arguments: args }, headers: { "X-Api-Key" => @key.display_key }, as: :json
    end
end
