# frozen_string_literal: true

require "jwt"

module McpAuthentikTestHelper
  KEY = OpenSSL::PKey::RSA.generate(2048)
  ENV_KEYS = %w[RELAY_MCP_ENABLED RELAY_MCP_URL RELAY_MCP_CLIENT_IDS RELAY_MCP_API_KEYS_ENABLED
    RELAY_MCP_AUTHENTIK_ENABLED RELAY_MCP_AUTHENTIK_ISSUER RELAY_MCP_AUTHENTIK_CLIENT_ID
    RELAY_MCP_AUTHENTIK_MODE RELAY_MCP_AUTHENTIK_BINDINGS].freeze

  def setup_authentik
    @saved_env = ENV.to_h.slice(*ENV_KEYS)
    ENV["RELAY_MCP_ENABLED"] = "true"
    ENV["RELAY_MCP_URL"] = "https://relay.example/mcp"
    ENV["RELAY_MCP_AUTHENTIK_ENABLED"] = "true"
    ENV["RELAY_MCP_AUTHENTIK_ISSUER"] = "https://auth.example/application/o/#{SecureRandom.hex(8)}/"
    ENV["RELAY_MCP_AUTHENTIK_CLIENT_ID"] = "relay-only"
    ENV["RELAY_MCP_AUTHENTIK_MODE"] = "authentik"
    @user = users(:family_admin)
    bind_identity
    @metadata = {
      issuer: Mcp::Authentik.issuer, jwks_uri: "#{Mcp::Authentik.issuer}jwks/",
      authorization_endpoint: "https://auth.example/application/o/authorize/", token_endpoint: "https://auth.example/application/o/token/",
      code_challenge_methods_supported: [ "S256" ], grant_types_supported: %w[authorization_code refresh_token],
      token_endpoint_auth_methods_supported: [ "client_secret_basic" ]
    }
    @jwk = JWT::JWK.new(KEY, "primary").export
    @discovery_request = stub_request(:get, "#{Mcp::Authentik.issuer}.well-known/openid-configuration")
      .to_return(status: 200, body: @metadata.to_json)
    @jwks_request = stub_request(:get, @metadata[:jwks_uri]).to_return(status: 200, body: { keys: [ @jwk ] }.to_json)
    @claims = { "iss" => Mcp::Authentik.issuer, "aud" => Mcp::Authentik.client_id, "azp" => Mcp::Authentik.client_id,
      "sub" => "stable-subject", "uid" => "authentik-user", "exp" => 10.minutes.from_now.to_i,
      "iat" => Time.now.to_i, "scope" => "openid offline_access read_write" }
  end

  def teardown_authentik
    ENV_KEYS.each { |key| ENV[key] = @saved_env[key] }
  end

  def bind_identity(scopes: %w[read_write], user: @user)
    ENV["RELAY_MCP_AUTHENTIK_BINDINGS"] = [ { issuer: Mcp::Authentik.issuer, sub: "stable-subject", user_id: user.id, scopes: scopes } ].to_json
  end

  def jwt(changes = {}, key: KEY, header: {}, **claim_changes)
    parts = [ { alg: "RS256", kid: "primary", typ: "JWT" }.merge(header), @claims.merge(changes).merge(claim_changes) ]
      .map { |value| Base64.urlsafe_encode64(value.to_json, padding: false) }
    signed = parts.join(".")
    "#{signed}.#{Base64.urlsafe_encode64(key.sign('SHA256', signed), padding: false)}"
  end
end
