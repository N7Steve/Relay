# frozen_string_literal: true

require "test_helper"
require Rails.root.join("test/support/mcp_authentik_test_helper")

class McpMetadataControllerTest < ActionDispatch::IntegrationTest
  include McpAuthentikTestHelper
  setup { setup_authentik }
  teardown { teardown_authentik }

  test "protected resource advertises only Authentik when enabled" do
    get "/.well-known/oauth-protected-resource/mcp"

    assert_response :success
    assert_equal Mcp::Configuration.resource, response.parsed_body.fetch("resource")
    assert_equal [ Mcp::Authentik.issuer ], response.parsed_body.fetch("authorization_servers")
    assert_equal %w[read read_write], response.parsed_body.fetch("scopes_supported")
    assert_equal [ "header" ], response.parsed_body.fetch("bearer_methods_supported")
  end

  test "protected resource advertises only Relay when Authentik is disabled or unset" do
    [ "false", nil ].each do |enabled|
      ENV["RELAY_MCP_AUTHENTIK_ENABLED"] = enabled
      get "/.well-known/oauth-protected-resource/mcp"

      assert_response :success
      assert_equal Mcp::Configuration.resource, response.parsed_body.fetch("resource")
      assert_equal [ "https://relay.example" ], response.parsed_body.fetch("authorization_servers")
    end
  end

  test "native authorization server metadata stays available in both modes" do
    %w[true false].each do |enabled|
      ENV["RELAY_MCP_AUTHENTIK_ENABLED"] = enabled
      get "/.well-known/oauth-authorization-server"

      assert_response :success
      assert_equal "https://relay.example", response.parsed_body.fetch("issuer")
      assert_equal "https://relay.example/oauth/authorize", response.parsed_body.fetch("authorization_endpoint")
      assert_equal "https://relay.example/oauth/token", response.parsed_body.fetch("token_endpoint")
      assert_equal "https://relay.example/oauth/revoke", response.parsed_body.fetch("revocation_endpoint")
      assert_equal %w[authorization_code refresh_token], response.parsed_body.fetch("grant_types_supported")
      assert_equal [ "S256" ], response.parsed_body.fetch("code_challenge_methods_supported")
    end
  end
end
