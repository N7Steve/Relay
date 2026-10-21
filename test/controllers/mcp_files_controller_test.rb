# frozen_string_literal: true

require "test_helper"

class McpFilesControllerTest < ActionDispatch::IntegrationTest
  test "MCP file channel enforces activation audience client and Origin on binary requests" do
    saved = ENV.to_h.slice("RELAY_MCP_ENABLED", "RELAY_MCP_URL", "RELAY_MCP_CLIENT_IDS")
    ENV["RELAY_MCP_ENABLED"] = "true"
    ENV["RELAY_MCP_URL"] = "https://relay.example/mcp"
    client = Doorkeeper::Application.create!(name: "Files client", redirect_uri: "https://client.example/callback", confidential: false, scopes: "read_write")
    ENV["RELAY_MCP_CLIENT_IDS"] = client.uid
    token = Doorkeeper::AccessToken.create!(application: client, resource_owner_id: users(:family_admin).id, scopes: "read_write", expires_in: 3600, mcp_resource: ENV["RELAY_MCP_URL"])
    get "/mcp/files/download", params: { kind: "statement", id: SecureRandom.uuid }, headers: { "Authorization" => "Bearer #{token.plaintext_token}", "Origin" => "https://evil.example" }
    assert_response :forbidden
    token.update!(mcp_resource: nil)
    post "/mcp/files", params: {}, headers: { "Authorization" => "Bearer #{token.plaintext_token}" }
    assert_response :unauthorized
    ENV["RELAY_MCP_ENABLED"] = "false"
    post "/mcp/files", params: {}
    assert_response :not_found
  ensure
    saved&.each { |key, value| ENV[key] = value }
    %w[RELAY_MCP_ENABLED RELAY_MCP_URL RELAY_MCP_CLIENT_IDS].each { |key| ENV.delete(key) unless saved&.key?(key) }
  end
end
