# frozen_string_literal: true

require "test_helper"

class McpOauthTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    sign_in @user
    @application = Doorkeeper::Application.create!(name: "Delegated MCP", redirect_uri: "https://client.example/callback", confidential: false, scopes: "read read_write")
    @saved_env = ENV.to_h.slice("RELAY_MCP_ENABLED", "RELAY_MCP_URL", "RELAY_MCP_CLIENT_IDS")
    ENV["RELAY_MCP_ENABLED"] = "true"
    ENV["RELAY_MCP_URL"] = "https://relay.example/mcp"
    ENV["RELAY_MCP_CLIENT_IDS"] = @application.uid
    @verifier = SecureRandom.urlsafe_base64(48)
    @authorization = { client_id: @application.uid, redirect_uri: @application.redirect_uri, response_type: "code", scope: "read",
      resource: ENV["RELAY_MCP_URL"], code_challenge_method: "S256", code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false), state: "test-state" }
  end

  teardown do
    %w[RELAY_MCP_ENABLED RELAY_MCP_URL RELAY_MCP_CLIENT_IDS].each { |key| ENV[key] = @saved_env[key] }
  end

  test "consent persists resource and PKCE binds code exchange refresh and revocation" do
    get "/oauth/authorize", params: @authorization
    assert_response :success, response.body
    assert_select "input[name=resource][value=?]", ENV["RELAY_MCP_URL"]
    post "/oauth/authorize", params: @authorization
    assert_response :redirect
    code = Rack::Utils.parse_query(URI.parse(response.location).query).fetch("code")
    grant = Doorkeeper::AccessGrant.by_token(code)
    assert grant, "Authorization code must resolve to a stored grant"
    assert_equal ENV["RELAY_MCP_URL"], grant.mcp_resource
    exchange = { client_id: @application.uid, grant_type: "authorization_code", code: code,
      redirect_uri: @application.redirect_uri, code_verifier: @verifier, resource: ENV["RELAY_MCP_URL"] }
    post "/oauth/token", params: exchange.merge(resource: "https://wrong.example/mcp")
    assert_response :bad_request
    refute grant.reload.revoked?
    post "/oauth/token", params: exchange.merge(code_verifier: "incorrect")
    assert_response :bad_request
    post "/oauth/token", params: exchange
    assert_response :success, response.body
    token = response.parsed_body.fetch("access_token")
    refresh = response.parsed_body.fetch("refresh_token")
    assert_equal ENV["RELAY_MCP_URL"], Doorkeeper::AccessToken.by_token(token).mcp_resource
    post "/oauth/token", params: exchange
    assert_response :bad_request
    post "/oauth/token", params: { client_id: @application.uid, grant_type: "refresh_token", refresh_token: refresh, resource: ENV["RELAY_MCP_URL"] }
    assert_response :success, response.body
    renewed = response.parsed_body.fetch("access_token")
    assert_equal ENV["RELAY_MCP_URL"], Doorkeeper::AccessToken.by_token(renewed).mcp_resource
    post "/oauth/revoke", params: { client_id: @application.uid, token: renewed }
    assert_response :success
    assert Doorkeeper::AccessToken.by_token(renewed).revoked?
  end

  test "MCP authorization requires approved client exact resource and S256" do
    [ @authorization.except(:resource), @authorization.merge(resource: "https://other.example/mcp"),
      @authorization.merge(code_challenge_method: "plain"), @authorization.except(:code_challenge) ].each do |args|
      post "/oauth/authorize", params: args
      assert_response :bad_request, response.body
    end
    ENV["RELAY_MCP_CLIENT_IDS"] = ""
    post "/oauth/authorize", params: @authorization
    assert_response :bad_request
  end
end
