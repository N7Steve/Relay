# frozen_string_literal: true

require "test_helper"
require Rails.root.join("test/support/mcp_authentik_test_helper")

class McpAuthentikTest < ActionDispatch::IntegrationTest
  include McpAuthentikTestHelper
  setup { setup_authentik }
  teardown { teardown_authentik }

  test "MCP HTTP discovery initialization notification catalog and authorized account reads" do
    get "/.well-known/oauth-protected-resource/mcp"
    assert_equal [ Mcp::Authentik.issuer, "https://relay.example" ], response.parsed_body["authorization_servers"]
    get "/.well-known/oauth-authorization-server"
    assert_equal "https://relay.example", response.parsed_body["issuer"]
    rpc("initialize", { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "OAuth MCP", version: "1" } })
    assert_response :success
    assert_equal "2025-11-25", response.parsed_body.dig("result", "protocolVersion")
    post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json, headers: headers
    assert_response :accepted
    rpc("tools/list")
    assert_response :success
    assert response.parsed_body.dig("result", "tools").any?
    rpc("tools/call", { name: "get_context", arguments: {} })
    assert_equal @user.id, result.dig("user", "id")
    rpc("tools/call", { name: "list_accounts", arguments: {} })
    assert_response :success
    refute response.parsed_body.dig("result", "isError"), response.body
  end

  test "read-only local ceiling hides writes and rejects manual calls" do
    bind_identity(scopes: %w[read])
    rpc("tools/list")
    assert response.parsed_body.dig("result", "tools").all? { |tool| tool.dig("annotations", "readOnlyHint") }
    assert_no_difference [ "Mcp::ChangeSet.count", "Tag.count" ] do
      propose_tag
    end
    assert_equal "forbidden", result["error"]
  end

  test "native account and family boundaries apply even to Authentik authenticated admin" do
    account = accounts(:depository)
    credential = Mcp::AuthentikVerifier.instance.verify(jwt)
    access = Api::Access.new(user: credential.user, scopes: credential.scopes, credential: credential)
    assert access.allowed?(account, :read)
    account.update!(owner: users(:family_member))
    assert_not access.allowed?(account, :write)
    foreign_account = users(:empty).family.accounts.create!(name: "Other family", balance: 0, currency: "USD", accountable: Depository.new, owner: users(:empty))
    assert_not access.allowed?(foreign_account, :read)
    rpc("tools/call", { name: "get_account", arguments: { account_id: foreign_account.id } })
    assert response.parsed_body.dig("result", "isError"), response.body
  end

  test "writes remain idempotent proposals and only web approval applies them" do
    assert_no_difference "Tag.count" do
      assert_difference "Mcp::ChangeSet.count", 1 do
        propose_tag
        assert_equal "pending_approval", result["status"]
        @set = Mcp::ChangeSet.find(result.fetch("change_set_id"))
        propose_tag
        assert_equal @set.id, result["change_set_id"]
      end
    end
    assert_equal "Mcp::AuthentikCredential", @set.authority["credential_type"]
    refute_includes @set.authority.to_json, jwt
    post approve_settings_pending_change_path(@set), params: { review_token: @set.review_token }, headers: { "Authorization" => "Bearer #{jwt}" }
    assert_response :redirect
    assert_equal "pending", @set.reload.status
    sign_in @user
    post approve_settings_pending_change_path(@set), params: { review_token: @set.review_token }
    assert_redirected_to settings_pending_change_path(@set)
    assert_equal "approved", @set.reload.status
    assert_difference "Tag.count", 1 do
      Mcp::ApplyChangeSetJob.perform_now(@set)
    end
    assert_equal "applied", @set.reload.status
    assert_no_difference "Tag.count" do
      Mcp::ApplyChangeSetJob.perform_now(@set)
    end
  end

  test "proposal authority rechecks binding scope user activity enablement and expiry" do
    propose_tag
    set = Mcp::ChangeSet.find(result.fetch("change_set_id"))
    bind_identity(scopes: %w[read])
    assert_raises(Api::Access::Forbidden) { set.approve!(actor: @user, token: set.review_token) }
    bind_identity
    set.approve!(actor: @user, token: set.review_token)
    ENV["RELAY_MCP_AUTHENTIK_ENABLED"] = "false"
    assert_no_difference "Tag.count" do
      Mcp::ApplyChangeSetJob.perform_now(set)
    end
    assert_equal "failed", set.reload.status
    ENV["RELAY_MCP_AUTHENTIK_ENABLED"] = "true"
    authority = set.authority
    bind_identity(user: users(:family_member))
    assert_raises(Api::Access::Forbidden) { Api::Access.from_delegation!(authority, family: @user.family) }
    bind_identity
    @user.update_column(:active, false)
    assert_raises(Api::Access::Forbidden) { Api::Access.from_delegation!(authority, family: @user.family) }
    @user.update_column(:active, true)
    travel 11.minutes do
      assert_raises(Api::Access::Forbidden) { Api::Access.from_delegation!(authority, family: @user.family) }
    end
  end

  test "Authentik is MCP only and native OAuth API keys and web sessions keep their authentication" do
    auth = { "Authorization" => "Bearer #{jwt}" }
    get "/api/v1/context", headers: auth
    assert_response :unauthorized
    key = ApiKey.create!(user: @user, name: "Compatibility", scopes: %w[read], source: "web", display_key: SecureRandom.hex(32))
    ENV["RELAY_MCP_API_KEYS_ENABLED"] = "true"
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json, headers: headers.except("Authorization").merge("X-Api-Key" => key.display_key)
    assert_response :success
    get "/api/v1/context", headers: { "X-Api-Key" => key.display_key }
    assert_response :success
    application = Doorkeeper::Application.create!(name: "Native", redirect_uri: "https://client.example/callback", confidential: false, scopes: "read")
    ENV["RELAY_MCP_CLIENT_IDS"] = application.uid
    token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: @user.id, scopes: "read", expires_in: 600, mcp_resource: Mcp::Configuration.resource)
    rpc("ping", {}, token: token.token)
    assert_response :success
    token.update!(mcp_resource: nil)
    rpc("ping", {}, token: token.token)
    assert_response :unauthorized
    get "/api/v1/context", headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :success
    sign_in @user
    rpc("ping", {}, token: "invalid.jwt.token")
    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], "https://relay.example/.well-known/oauth-protected-resource/mcp"
    ENV["RELAY_MCP_AUTHENTIK_CLIENT_ID"] = ""
    get "/.well-known/oauth-protected-resource/mcp"
    assert_response :service_unavailable
    ENV["RELAY_MCP_AUTHENTIK_CLIENT_ID"] = "relay-only"
    ENV["RELAY_MCP_AUTHENTIK_ENABLED"] = "false"
    rpc("ping")
    assert_response :unauthorized
    get "/.well-known/oauth-protected-resource/mcp"
    assert_equal [ "https://relay.example" ], response.parsed_body["authorization_servers"]
  end

  private
    def result
      response.parsed_body.dig("result", "structuredContent")
    end

    def propose_tag
      rpc("tools/call", { name: "create_tag", arguments: { name: "OAuth proposed tag", idempotency_key: "authentik-tag" } })
      assert_response :success, response.body
    end

    def rpc(method, params = {}, token: jwt)
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json, headers: headers.merge("Authorization" => "Bearer #{token}")
    end

    def headers
      { "Authorization" => "Bearer #{jwt}", "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream", "MCP-Protocol-Version" => "2025-11-25" }
    end
end
