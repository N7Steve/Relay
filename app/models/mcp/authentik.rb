# frozen_string_literal: true

# MCP-only identity configuration. Never consult web SSO/JIT provisioning.
class Mcp::Authentik
  Invalid = Class.new(StandardError)

  def self.enabled?
    ENV["RELAY_MCP_AUTHENTIK_ENABLED"] == "true"
  end

  def self.issuer
    ENV.fetch("RELAY_MCP_AUTHENTIK_ISSUER", "")
  end

  def self.client_id
    ENV.fetch("RELAY_MCP_AUTHENTIK_CLIENT_ID", "")
  end

  def self.mode
    ENV.fetch("RELAY_MCP_AUTHENTIK_MODE", "resource")
  end

  def self.validate!
    uri = URI.parse(issuer)
    unless enabled? && Mcp::Configuration.enabled? && uri.scheme == "https" && uri.host.present? &&
        uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && issuer.end_with?("/") &&
        client_id.present? && mode.in?(%w[resource authentik])
      raise Invalid, "Invalid Authentik MCP configuration"
    end
  rescue URI::InvalidURIError
    raise Invalid, "Invalid Authentik issuer"
  end

  def self.audience
    mode == "authentik" ? client_id : Mcp::Configuration.resource
  end

  def self.binding!(subject)
    validate!
    bindings = JSON.parse(ENV.fetch("RELAY_MCP_AUTHENTIK_BINDINGS", "[]"))
    unless bindings.is_a?(Array) && bindings.all? { |row| row.is_a?(Hash) } &&
        bindings.map { |row| [ row["issuer"], row["sub"] ] }.uniq.size == bindings.size
      raise Invalid, "Ambiguous Authentik bindings"
    end
    row = bindings.find { |entry| entry["issuer"] == issuer && entry["sub"] == subject }
    unless row && UuidFormat.valid?(row["user_id"]) && row["scopes"].is_a?(Array) &&
        row["scopes"].any? && (row["scopes"] - %w[read read_write]).empty?
      raise Invalid, "Authentik identity is not authorized"
    end
    row
  rescue JSON::ParserError
    raise Invalid, "Invalid Authentik bindings"
  end
end
