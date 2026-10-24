# frozen_string_literal: true

class McpMetadataController < ActionController::Base
  before_action -> { head :not_found unless Mcp::Configuration.enabled? && Mcp::Configuration.resource.present? }

  def resource
    Mcp::Authentik.validate! if Mcp::Authentik.enabled?
    render json: {
      resource: Mcp::Configuration.resource,
      authorization_servers: Mcp::Authentik.enabled? ? [ Mcp::Authentik.issuer, issuer ] : [ issuer ],
      scopes_supported: %w[read read_write],
      bearer_methods_supported: [ "header" ]
    }
  rescue Mcp::Authentik::Invalid
    head :service_unavailable
  end

  def authorization_server
    render json: {
      issuer: issuer,
      authorization_endpoint: "#{issuer}/oauth/authorize",
      token_endpoint: "#{issuer}/oauth/token",
      revocation_endpoint: "#{issuer}/oauth/revoke",
      response_types_supported: [ "code" ],
      grant_types_supported: %w[authorization_code refresh_token],
      code_challenge_methods_supported: [ "S256" ],
      scopes_supported: %w[read read_write],
      token_endpoint_auth_methods_supported: %w[none client_secret_basic client_secret_post]
    }
  end

  private
    def issuer
      Mcp::Configuration.resource.delete_suffix("/mcp")
    end
end
