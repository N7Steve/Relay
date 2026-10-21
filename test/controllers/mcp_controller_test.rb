# frozen_string_literal: true

require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @key = ApiKey.create!(user: @user, name: "MCP", scopes: %w[read_write], source: "web", display_key: "mcp_#{SecureRandom.hex(12)}")
    @old_env = ENV.to_h.slice("RELAY_MCP_ENABLED", "RELAY_MCP_URL", "RELAY_MCP_API_KEYS_ENABLED", "RELAY_MCP_CLIENT_IDS")
    ENV["RELAY_MCP_ENABLED"] = "true"
    ENV["RELAY_MCP_URL"] = "https://relay.example/mcp"
    ENV["RELAY_MCP_API_KEYS_ENABLED"] = "true"
  end

  teardown do
    %w[RELAY_MCP_ENABLED RELAY_MCP_URL RELAY_MCP_API_KEYS_ENABLED RELAY_MCP_CLIENT_IDS].each { |key| ENV[key] = @old_env[key] }
  end

  test "legacy initialize catalog pagination tool execution and notification" do
    rpc("initialize", { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "Test", version: "1" } })
    assert_response :success, response.body
    assert_equal "2025-11-25", response.parsed_body.dig("result", "protocolVersion")
    rpc("tools/list")
    assert_response :success
    first = response.parsed_body.fetch("result")
    assert_equal 25, first.fetch("tools").length
    rpc("tools/list", { cursor: first.fetch("nextCursor") })
    assert_response :success
    assert response.parsed_body.dig("result", "tools").any?
    rpc("tools/call", { name: "get_context", arguments: {} })
    assert_response :success
    assert_equal @user.id, response.parsed_body.dig("result", "structuredContent", "user", "id")
    post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json, headers: rpc_headers
    assert_response :accepted
    assert_empty response.body
  end

  test "modern requests need no initialization and enforce header body consistency" do
    params = { name: "get_context", arguments: {}, _meta: {
      "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
      "io.modelcontextprotocol/clientInfo" => { name: "Modern", version: "1" },
      "io.modelcontextprotocol/clientCapabilities" => {}
    } }
    rpc("tools/call", params, headers: { "MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "tools/call", "Mcp-Name" => "get_context" })
    assert_response :success, response.body
    assert_equal "complete", response.parsed_body.dig("result", "resultType")
    rpc("server/discover", params.except(:name, :arguments), headers: { "MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "server/discover" })
    assert_response :success, response.body
    assert_includes response.parsed_body.dig("result", "supportedVersions"), "2026-07-28"
    assert_equal "Relay", response.parsed_body.dig("result", "_meta", "io.modelcontextprotocol/serverInfo", "name")
    rpc("tools/call", params, headers: { "MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "tools/list" })
    assert_response :bad_request
    assert_equal(-32020, response.parsed_body.dig("error", "code"))
    rpc("tools/list", {}, headers: { "MCP-Protocol-Version" => "1900-01-01" })
    assert_response :bad_request
    assert_equal(-32022, response.parsed_body.dig("error", "code"))
  end

  test "disabled instance origin authentication and unsupported HTTP methods" do
    rpc("ping", {}, headers: { "Origin" => "https://evil.example" })
    assert_response :forbidden
    rpc("ping", {}, headers: { "Origin" => "https://relay.example" })
    assert_response :success
    post "/mcp", params: {}.to_json, headers: rpc_headers.except("X-Api-Key")
    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], "oauth-protected-resource/mcp"
    get "/mcp", headers: rpc_headers
    assert_response :method_not_allowed
    ENV["RELAY_MCP_ENABLED"] = "false"
    rpc("ping")
    assert_response :not_found
  end

  test "malformed batch unknown methods oversized requests and invalid arguments" do
    [ "{", "[]", '{"jsonrpc":"2.0","method":"ping","params":[]}' ].each do |body|
      post "/mcp", params: body, headers: rpc_headers
      assert_response :bad_request, response.body
    end
    rpc("does/not/exist")
    assert_response :not_found
    post "/mcp", params: ("x" * (McpController::MAX_BYTES + 1)), headers: rpc_headers
    assert_response :payload_too_large
    rpc("tools/call", { name: "list_accounts", arguments: { per_page: 101 } })
    assert_response :success
    assert response.parsed_body.dig("result", "isError")
  end

  test "read credential cannot call writes even when bypassing catalog" do
    @key.update!(scopes: %w[read])
    rpc("tools/list")
    assert response.parsed_body.dig("result", "tools").all? { |tool| tool.dig("annotations", "readOnlyHint") }
    rpc("tools/call", { name: "create_tag", arguments: { name: "Denied", idempotency_key: "denied" } })
    assert_response :success
    assert_equal "forbidden", response.parsed_body.dig("result", "structuredContent", "error")
  end

  test "OAuth token audience expiry revocation and per request identity" do
    application = Doorkeeper::Application.create!(name: "MCP test", redirect_uri: "https://client.example/callback", confidential: false, scopes: "read")
    ENV["RELAY_MCP_CLIENT_IDS"] = application.uid
    token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: @user.id, scopes: "read", expires_in: 3600, mcp_resource: ENV["RELAY_MCP_URL"])
    auth = { "Authorization" => "Bearer #{token.token}" }
    rpc("tools/call", { name: "get_context", arguments: {} }, headers: auth)
    assert_response :success
    assert_equal @user.id, response.parsed_body.dig("result", "structuredContent", "user", "id")
    get "/api/v1/context", headers: auth
    assert_response :unauthorized
    token.update!(mcp_resource: "https://other.example/mcp")
    rpc("ping", {}, headers: auth)
    assert_response :unauthorized
    token.update!(mcp_resource: ENV["RELAY_MCP_URL"], created_at: 2.hours.ago)
    rpc("ping", {}, headers: auth)
    assert_response :unauthorized
    token.update!(created_at: Time.current, revoked_at: Time.current)
    rpc("ping", {}, headers: auth)
    assert_response :unauthorized
    rpc("tools/call", { name: "get_context", arguments: {} })
    assert_response :success
    assert_equal @user.id, response.parsed_body.dig("result", "structuredContent", "user", "id")
  end

  test "metadata advertises preregistration PKCE and protected resource" do
    get "/.well-known/oauth-protected-resource/mcp"
    assert_response :success
    assert_equal ENV["RELAY_MCP_URL"], response.parsed_body.fetch("resource")
    get "/.well-known/oauth-authorization-server"
    assert_response :success
    assert_equal [ "S256" ], response.parsed_body.fetch("code_challenge_methods_supported")
    refute response.parsed_body.key?("registration_endpoint")
  end

  private
    def rpc(method, params = {}, headers: {})
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json, headers: rpc_headers.merge(headers)
    end

    def rpc_headers
      { "X-Api-Key" => @key.display_key, "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream", "MCP-Protocol-Version" => "2025-11-25" }
    end
end
