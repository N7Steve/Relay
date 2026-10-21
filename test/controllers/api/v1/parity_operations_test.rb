# frozen_string_literal: true

require "test_helper"

class Api::V1::ParityOperationsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @key = ApiKey.create!(user: @user, name: "Parity", scopes: %w[read], source: "web", display_key: "parity_#{SecureRandom.hex(12)}")
  end

  test "read keys can inspect both transfer ends but never a private counterparty" do
    source, destination = accounts(:depository), accounts(:investment)
    transfer = Transfer::Creator.new(family: @user.family, source_account_id: source.id, destination_account_id: destination.id, date: Date.current, amount: 20).create
    assert transfer.persisted?, transfer.errors.full_messages.to_sentence
    invoke("get_transfer", transfer_id: transfer.id)
    assert_response :success, response.body
    invoke("get_transaction", transaction_id: transfer.outflow_transaction_id)
    assert_response :success
    invoke("list_transfers", {})
    assert_response :success
    destination.update!(owner: users(:family_member))
    destination.account_shares.where(user: @user).destroy_all
    invoke("get_transfer", transfer_id: transfer.id)
    assert_response :not_found
    invoke("list_transfers", {})
    assert_response :success
    assert_not response.parsed_body.fetch("data").any? { |row| row["id"] == transfer.id }
  end

  test "local security discovery is limited to held and traded securities" do
    private_security = Security::Resolver.new("UNRELATED").resolve
    invoke("list_local_securities", {})
    assert_response :success
    assert response.parsed_body.fetch("data").any? { |row| row["id"] == securities(:aapl).id }
    invoke("get_local_security", security_id: private_security.id)
    assert_response :not_found
  end

  test "insight status and refresh retain preview full visibility and credential scope" do
    @key.update!(scopes: %w[read_write])
    invoke("list_insights", {})
    assert_response :forbidden
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => true))
    invoke("list_insights", {})
    assert_response :success
    invoke("set_insight_status", insight_id: insights(:spending_anomaly_dining).id, status: "acknowledged", idempotency_key: "ack")
    assert_response :success, response.body
    assert insights(:spending_anomaly_dining).reload.acknowledged?
    assert_enqueued_with(job: ApiIntegrationJob) do
      invoke("refresh_insights", idempotency_key: "refresh")
      assert_response :success
    end
  end

  test "capabilities and explicit Sankey use server engines without granting write access" do
    invoke("get_capabilities", {})
    assert_response :success
    assert response.parsed_body.fetch("tools").include?("get_transaction")
    assert_not response.parsed_body.fetch("tools").include?("update_profile")
    invoke("get_cash_flow", month: Date.current.beginning_of_month.iso8601, include_sankey: true)
    assert_response :success, response.body
  end

  private
    def invoke(name, args)
      post "/api/v1/actions/#{name}", params: { arguments: args }, headers: { "X-Api-Key" => @key.display_key }, as: :json
    end
end
