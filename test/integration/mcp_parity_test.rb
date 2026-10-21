# frozen_string_literal: true

require "test_helper"

class McpParityTest < ActionDispatch::IntegrationTest
  setup do
    @saved = ENV.to_h.slice("RELAY_MCP_ENABLED", "RELAY_MCP_URL", "RELAY_MCP_API_KEYS_ENABLED")
    ENV["RELAY_MCP_ENABLED"] = "true"
    ENV["RELAY_MCP_URL"] = "https://relay.example/mcp"
    ENV["RELAY_MCP_API_KEYS_ENABLED"] = "true"
    @user = users(:family_admin)
    @key = ApiKey.create!(user: @user, name: "Conformance", scopes: %w[read_write], source: "web", display_key: "conformance_#{SecureRandom.hex(12)}")
  end

  teardown do
    %w[RELAY_MCP_ENABLED RELAY_MCP_URL RELAY_MCP_API_KEYS_ENABLED].each { |key| ENV[key] = @saved[key] }
  end

  test "REST writes stay immediate while MCP proposes a separate approved operation" do
    args = { account_id: accounts(:depository).id, date: Date.current.iso8601, amount: "14.25", name: "Cross transport", idempotency_key: "transport-replay" }
    assert_difference "Transaction.count", 1 do
      post "/api/v1/actions/create_transaction", params: { arguments: args }, headers: api_headers, as: :json
      assert_response :success
      original = response.parsed_body
      rpc("create_transaction", args)
      assert_response :success
      assert_equal false, response.parsed_body.dig("result", "isError")
      assert_equal "pending_approval", response.parsed_body.dig("result", "structuredContent", "status")
      assert_equal "Cross transport", original.fetch("name")
    end
    assert_equal 1, Api::Operation.where(user: @user, key: "transport-replay").count
  end

  test "permission changes are checked before a cross transport replay" do
    args = { first_name: "Before downgrade", idempotency_key: "profile-downgrade" }
    post "/api/v1/actions/update_profile", params: { arguments: args }, headers: api_headers, as: :json
    assert_response :success
    @key.update!(scopes: %w[read])
    rpc("update_profile", args)
    assert_equal true, response.parsed_body.dig("result", "isError")
    assert_equal "forbidden", response.parsed_body.dig("result", "structuredContent", "error")
  end

  test "oversized approved results roll back the operation and stop the proposal" do
    entry = accounts(:depository).entries.create!(name: "Large split", date: Date.current, amount: 100, currency: "USD", entryable: Transaction.new)
    args = { transaction_id: entry.entryable_id, idempotency_key: "oversized-result",
      splits: Array.new(100) { { name: "n" * 2000, notes: "x" * 400, amount: "1" } } }
    assert_operator JSON.generate(args).bytesize, :<, McpController::MAX_BYTES
    assert_no_difference "Entry.count" do
      rpc("split_transaction", args)
      assert_response :success
      assert_equal false, response.parsed_body.dig("result", "isError")
      set = Mcp::ChangeSet.find(response.parsed_body.dig("result", "structuredContent", "change_set_id"))
      set.approve!(actor: @user, token: set.review_token)
      set.apply!
      assert_equal "failed", set.reload.status
    end
    assert_equal 0, entry.reload.child_entries.count
    assert_not Api::Operation.exists?(user: @user, key: "oversized-result")
    assert_not Api::Operation.where(user: @user).where("key LIKE ?", "mcp-approved:%").exists?
  end

  private
    def api_headers
      { "X-Api-Key" => @key.display_key }
    end

    def rpc(name, args)
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: args } },
        headers: api_headers.merge("Accept" => "application/json, text/event-stream", "MCP-Protocol-Version" => "2025-11-25"), as: :json
    end
end
