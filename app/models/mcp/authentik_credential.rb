# frozen_string_literal: true

# Retains only verified authority, never a JWT, refresh token or client secret.
class Mcp::AuthentikCredential
  attr_reader :user, :scopes, :claims

  def initialize(claims)
    @claims = claims.slice("iss", "sub", "azp", "exp", "scope")
    binding = Mcp::Authentik.binding!(claims["sub"])
    @user = User.find_by(id: binding.fetch("user_id"))
    raise Mcp::Authentik::Invalid, "Inactive Authentik actor" unless user&.active?
    # read_write includes read, but openid never implies either permission.
    granted = claims.fetch("scope", "").split
    granted << "read" if granted.include?("read_write")
    ceiling = binding.fetch("scopes").dup
    ceiling << "read" if ceiling.include?("read_write")
    @scopes = granted & ceiling & %w[read read_write]
    raise Mcp::Authentik::Invalid, "No effective MCP scope" if scopes.empty?
  end

  def id
    Digest::SHA256.hexdigest([ claims["iss"], claims["sub"], claims["azp"], user.id,
      Mcp::Authentik.mode, Mcp::Configuration.resource ].to_json)
  end

  def application
    nil
  end

  def self.from_delegation!(authority, actor:)
    claims = authority.fetch("authentik", {})
    unless Mcp::Authentik.enabled? && claims["iss"] == Mcp::Authentik.issuer &&
        claims["azp"] == Mcp::Authentik.client_id && claims["exp"].is_a?(Integer) && claims["exp"] > Time.now.to_i
      raise Mcp::Authentik::Invalid, "Authentik authority expired or disabled"
    end
    credential = new(claims)
    unless credential.user.id == actor.id && credential.id == authority["credential_id"]
      raise Mcp::Authentik::Invalid, "Authentik binding changed"
    end
    credential
  end
end
