# frozen_string_literal: true

require "jwt"
require "net/http"

class Mcp::AuthentikVerifier
  MAX_BYTES = 64.kilobytes
  INSTANCE_MUTEX = Mutex.new

  def self.instance
    Mcp::Authentik.validate!
    key = [ Mcp::Authentik.issuer, Mcp::Authentik.client_id, Mcp::Authentik.mode, Mcp::Configuration.resource ]
    INSTANCE_MUTEX.synchronize do
      if @configuration != key
        @instance = new
        @configuration = key
      end
      @instance
    end
  end

  def initialize
    @issuer = Mcp::Authentik.issuer
    @audience = Mcp::Authentik.audience
    @client_id = Mcp::Authentik.client_id
    @mutex = Mutex.new
  end

  def verify(raw)
    raise Mcp::Authentik::Invalid, "Invalid JWT size" unless raw.is_a?(String) && raw.bytesize <= 16.kilobytes
    # Untrusted headers select a key only; all authority comes from verified claims.
    _, header = JWT.decode(raw, nil, false)
    unless header["alg"] == "RS256" && header["typ"] == "JWT" && header["kid"].is_a?(String) && header["kid"].present?
      raise Mcp::Authentik::Invalid, "Invalid JWT header"
    end
    key = signing_key(header.fetch("kid"))
    # Check NumericDate types below instead of JWT's permissive to_i coercion.
    claims, = JWT.decode(raw, key, true, algorithms: [ "RS256" ], verify_iss: true, iss: @issuer,
      verify_aud: true, aud: @audience, verify_expiration: false, verify_not_before: false,
      required_claims: %w[iss aud sub exp iat azp uid scope])
    unless (claims["aud"] == @audience || claims["aud"] == [ @audience ]) && claims["azp"] == @client_id &&
        %w[sub uid].all? { |name| claims[name].is_a?(String) && claims[name].strip.present? } &&
        claims["scope"].is_a?(String) && claims["exp"].is_a?(Integer) && claims["exp"] > Time.now.to_i &&
        claims["iat"].is_a?(Integer) && claims["iat"] <= Time.now.to_i && claims["iat"] < claims["exp"] &&
        (!claims.key?("nbf") || (claims["nbf"].is_a?(Integer) && claims["nbf"] <= Time.now.to_i))
      raise Mcp::Authentik::Invalid, "Invalid access token claims"
    end
    Mcp::AuthentikCredential.new(claims)
  rescue JWT::DecodeError, OpenSSL::PKey::PKeyError, ArgumentError => error
    raise Mcp::Authentik::Invalid, error.class.name
  end

  private
    def signing_key(kid)
      @mutex.synchronize do
        now = Time.now.to_i
        raise Mcp::Authentik::Invalid, "Provider temporarily unavailable" if @retry_at && now < @retry_at
        refresh = @expires_at.nil? || now >= @expires_at || (!@keys.key?(kid) && now >= @refresh_after)
        if refresh
          begin
            metadata = fetch_json("#{@issuer}.well-known/openid-configuration")
            validate_metadata!(metadata)
            jwks = fetch_json(metadata.fetch("jwks_uri"))
            raise Mcp::Authentik::Invalid, "Invalid JWKS" unless jwks["keys"].is_a?(Array)
            keys = jwks["keys"].select do |jwk|
              jwk.is_a?(Hash) && jwk["kty"] == "RSA" && jwk["kid"].is_a?(String) &&
                jwk["kid"].present? && (!jwk.key?("use") || jwk["use"] == "sig") &&
                (!jwk.key?("alg") || jwk["alg"] == "RS256") &&
                (!jwk.key?("key_ops") || jwk["key_ops"] == [ "verify" ]) && !jwk.key?("d")
            end
            raise Mcp::Authentik::Invalid, "Ambiguous JWKS" if keys.map { |jwk| jwk["kid"] }.uniq.size != keys.size
            @keys = keys.to_h do |jwk|
              public_key = JWT::JWK.import(jwk).public_key
              raise Mcp::Authentik::Invalid, "Weak RSA key" if public_key.n.num_bits < 2048
              [ jwk.fetch("kid"), public_key ]
            end
            @expires_at = now + 600
            @refresh_after = now + 30
          rescue StandardError => error
            @retry_at = now + 30
            DebugLogEntry.capture(message: "Authentik MCP discovery/JWKS unavailable", category: "mcp", level: "error",
              source: self.class.name, metadata: { issuer: @issuer, error_class: error.class.name })
            raise Mcp::Authentik::Invalid, "Authentik metadata unavailable"
          end
        end
        @keys.fetch(kid) { raise Mcp::Authentik::Invalid, "Unknown signing key" }
      end
    end

    def validate_metadata!(metadata)
      unless metadata["issuer"] == @issuer && Array(metadata["code_challenge_methods_supported"]).include?("S256") &&
          Array(metadata["grant_types_supported"]).include?("authorization_code") &&
          (Array(metadata["token_endpoint_auth_methods_supported"]) & %w[client_secret_basic client_secret_post]).any?
        raise Mcp::Authentik::Invalid, "Incompatible discovery"
      end
      %w[jwks_uri authorization_endpoint token_endpoint].each { |name| trusted_uri!(metadata.fetch(name)) }
    end

    def trusted_uri!(url)
      uri, issuer = URI.parse(url), URI.parse(@issuer)
      unless uri.is_a?(URI::HTTPS) && uri.host == issuer.host && uri.port == issuer.port &&
          uri.userinfo.nil? && uri.fragment.nil? && uri.query.nil?
        raise Mcp::Authentik::Invalid, "Untrusted metadata URL"
      end
      uri
    end

    # No redirects, cookies, Authorization, TLS bypass or client credentials.
    def fetch_json(url)
      uri = trusted_uri!(url)
      body = +""
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        http.request(Net::HTTP::Get.new(uri, "Accept" => "application/json")) do |response|
          raise Mcp::Authentik::Invalid, "Metadata HTTP failure" unless response.code == "200"
          response.read_body do |chunk|
            body << chunk
            if body.bytesize > MAX_BYTES || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
              raise Mcp::Authentik::Invalid, "Metadata limit exceeded"
            end
          end
        end
      end
      result = JSON.parse(body, max_nesting: 16)
      raise Mcp::Authentik::Invalid, "Invalid metadata object" unless result.is_a?(Hash)
      result
    end
end
