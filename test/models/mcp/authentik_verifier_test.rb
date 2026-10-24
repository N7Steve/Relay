# frozen_string_literal: true

require "test_helper"
require Rails.root.join("test/support/mcp_authentik_test_helper")

class Mcp::AuthentikVerifierTest < ActiveSupport::TestCase
  include McpAuthentikTestHelper
  setup { setup_authentik }
  teardown { teardown_authentik }

  test "valid signed access token resolves only the explicit local binding and scope intersection" do
    verifier = Mcp::AuthentikVerifier.instance
    credential = verifier.verify(jwt)
    assert_equal @user, credential.user
    assert_equal %w[read_write read].sort, credential.scopes.sort
    refute_includes credential.claims.keys, "uid"
    bind_identity(scopes: %w[read])
    assert_equal %w[read], verifier.verify(jwt).scopes
    assert_equal %w[read], verifier.verify(jwt("scope" => "read")).scopes
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt("scope" => "openid")) }
    assert_requested @discovery_request, times: 1
    assert_requested @jwks_request, times: 1
  end

  test "rejects incorrect signature issuer audience client expiry ID tokens and unsafe algorithms" do
    verifier = Mcp::AuthentikVerifier.instance
    invalid_claims = [
      { "iss" => "https://other.example/" }, { "aud" => "other-client" },
      { "aud" => Mcp::Configuration.resource }, { "aud" => [ Mcp::Authentik.client_id, "other-client" ] },
      { "azp" => "ilos-client" }, { "exp" => 1.minute.ago.to_i }, { "exp" => "9999999999" },
      { "exp" => { "value" => 9999999999 } }, { "nbf" => "not-a-date" }, { "nbf" => [] },
      { "iat" => 1.minute.from_now.to_i }, { "uid" => nil }, { "azp" => nil }, { "sub" => "" },
      { "scope" => [ "read_write" ] }, { "nbf" => 1.minute.from_now.to_i }
    ]
    invalid_claims.each { |claims| assert_raises(Mcp::Authentik::Invalid, claims.inspect) { verifier.verify(jwt(claims)) } }
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt(key: OpenSSL::PKey::RSA.generate(2048))) }
    id_token = JWT.encode(@claims.except("uid", "azp"), KEY, "RS256", kid: "primary", typ: "JWT")
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify(id_token) }
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt(header: { typ: "at+jwt" })) }
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify(JWT.encode(@claims, "secret", "HS256", kid: "primary")) }
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify(JWT.encode(@claims, nil, "none")) }
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify("a" * 17.kilobytes) }
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify("not.a.jwt") }
  end

  test "resource mode never falls back to the client audience" do
    ENV.delete("RELAY_MCP_AUTHENTIK_MODE")
    verifier = Mcp::AuthentikVerifier.instance
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt) }
    assert_equal @user, verifier.verify(jwt("aud" => Mcp::Configuration.resource)).user
  end

  test "bindings reject unknown inactive deleted ambiguous or unauthorized users without provisioning" do
    verifier = Mcp::AuthentikVerifier.instance
    assert_no_difference "User.count" do
      assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt("sub" => "unknown", "email" => @user.email)) }
    end
    bind_identity(scopes: [])
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt) }
    bind_identity
    @user.update_column(:active, false)
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt) }
    @user.update_column(:active, true)
    rows = JSON.parse(ENV.fetch("RELAY_MCP_AUTHENTIK_BINDINGS"))
    ENV["RELAY_MCP_AUTHENTIK_BINDINGS"] = (rows + rows).to_json
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt) }
    rows[0]["user_id"] = SecureRandom.uuid
    ENV["RELAY_MCP_AUTHENTIK_BINDINGS"] = rows.to_json
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt) }
  end

  test "discovery requires same origin HTTPS S256 confidential clients and matching issuer" do
    [ { issuer: "https://other.example/" }, { code_challenge_methods_supported: [ "plain" ] },
      { token_endpoint_auth_methods_supported: [ "none" ] }, { grant_types_supported: [ "client_credentials" ] },
      { jwks_uri: "https://other.example/keys" }, { jwks_uri: "http://auth.example/keys" },
      { token_endpoint: "https://auth.example/token?secret=x" } ].each do |override|
      stub_request(:get, "#{Mcp::Authentik.issuer}.well-known/openid-configuration")
        .to_return(status: 200, body: @metadata.merge(override).to_json)
      assert_raises(Mcp::Authentik::Invalid) { Mcp::AuthentikVerifier.new.verify(jwt) }
    end
  end

  test "metadata and JWKS failures fail closed with bounded retry and sanitized diagnostics" do
    [ [ 302, "" ], [ 503, "" ], [ 200, "{" ], [ 200, "x" * 65.kilobytes ] ].each do |status, body|
      stub_request(:get, "#{Mcp::Authentik.issuer}.well-known/openid-configuration").to_return(status: status, body: body)
      assert_raises(Mcp::Authentik::Invalid) { Mcp::AuthentikVerifier.new.verify(jwt) }
    end
    stub_request(:get, "#{Mcp::Authentik.issuer}.well-known/openid-configuration").to_return(status: 200, body: @metadata.to_json)
    stub_request(:get, @metadata[:jwks_uri]).to_timeout
    verifier = Mcp::AuthentikVerifier.new
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt) }
    assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt) }
    assert_requested :get, @metadata[:jwks_uri], times: 1
    log = DebugLogEntry.order(:created_at).last
    refute_includes log.to_json, @claims["sub"]
  end

  test "rotation refreshes unknown keys after cooldown and expires cached keys without stale fallback" do
    verifier = Mcp::AuthentikVerifier.instance
    verifier.verify(jwt)
    rotated = JWT::JWK.new(KEY, "rotated").export
    stub_request(:get, @metadata[:jwks_uri]).to_return(status: 200, body: { keys: [ rotated ] }.to_json)
    3.times { assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt(header: { kid: "rotated" })) } }
    assert_requested @jwks_request, times: 1
    travel 31.seconds do
      assert_equal @user, verifier.verify(jwt(header: { kid: "rotated" })).user
      assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt) }
    end
    travel 601.seconds do
      stub_request(:get, @metadata[:jwks_uri]).to_return(status: 503)
      assert_raises(Mcp::Authentik::Invalid) { verifier.verify(jwt(header: { kid: "rotated" })) }
    end
  end

  test "unsafe configuration is rejected before any network request" do
    [ [ "RELAY_MCP_AUTHENTIK_ENABLED", "false" ], [ "RELAY_MCP_AUTHENTIK_MODE", "automatic" ],
      [ "RELAY_MCP_AUTHENTIK_ISSUER", "http://auth.example/" ], [ "RELAY_MCP_AUTHENTIK_CLIENT_ID", "" ] ].each do |name, value|
      old = ENV[name]
      ENV[name] = value
      assert_raises(Mcp::Authentik::Invalid) { Mcp::AuthentikVerifier.instance }
      ENV[name] = old
    end
    assert_not_requested :get, "#{Mcp::Authentik.issuer}.well-known/openid-configuration"
  end

  test "JWKS rejects ambiguous weak malformed or non signing keys" do
    weak = JWT::JWK.new(OpenSSL::PKey::RSA.generate(1024), "primary").export
    [ [ @jwk, @jwk ], [ weak ], [ @jwk.merge(use: "enc") ],
      [ @jwk.merge(alg: "HS256") ], [ @jwk.merge(key_ops: [ "sign" ]) ],
      [ @jwk.merge(d: "private-key-material") ], [ { kty: "RSA", kid: "primary", n: "invalid" } ] ].each do |keys|
      stub_request(:get, @metadata[:jwks_uri]).to_return(status: 200, body: { keys: keys }.to_json)
      assert_raises(Mcp::Authentik::Invalid) { Mcp::AuthentikVerifier.new.verify(jwt) }
    end
  end

  test "all access token claims are required" do
    %w[iss aud sub exp iat azp uid scope].each do |name|
      raw = JWT.encode(@claims.except(name), KEY, "RS256", kid: "primary", typ: "JWT")
      assert_raises(Mcp::Authentik::Invalid, name) { Mcp::AuthentikVerifier.instance.verify(raw) }
    end
  end
end
