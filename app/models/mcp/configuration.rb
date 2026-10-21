# frozen_string_literal: true

class Mcp::Configuration
  def self.enabled?
    return false unless ENV["RELAY_MCP_ENABLED"] == "true"
    uri = URI.parse(resource)
    uri.path == "/mcp" && uri.query.nil? && uri.fragment.nil? && uri.userinfo.nil? &&
      (uri.scheme == "https" || (uri.scheme == "http" && uri.host.in?(%w[127.0.0.1 localhost ::1])))
  rescue URI::InvalidURIError
    false
  end

  def self.resource
    ENV.fetch("RELAY_MCP_URL", "").delete_suffix("/")
  end

  def self.client_allowed?(uid)
    uid.present? && ENV.fetch("RELAY_MCP_CLIENT_IDS", "").split(",").map(&:strip).include?(uid)
  end

  def self.origin_allowed?(origin)
    return true if origin.blank?

    uri = URI.parse(resource)
    origin == "#{uri.scheme}://#{uri.host}#{uri.port == uri.default_port ? '' : ":#{uri.port}"}"
  rescue URI::InvalidURIError
    false
  end
end
