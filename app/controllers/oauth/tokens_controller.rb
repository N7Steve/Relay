# frozen_string_literal: true

class Oauth::TokensController < Doorkeeper::TokensController
  before_action :validate_mcp_resource, only: :create

  private
    def validate_mcp_resource
      credential = case params[:grant_type]
      when "authorization_code" then Doorkeeper::AccessGrant.by_token(params[:code])
      when "refresh_token" then Doorkeeper::AccessToken.by_refresh_token(params[:refresh_token])
      end
      params.delete(:mcp_resource)
      return if credential&.mcp_resource.blank? && params[:resource].blank?

      unless credential&.mcp_resource.present? && Mcp::Configuration.enabled? &&
          params[:resource] == credential.mcp_resource && credential.mcp_resource == Mcp::Configuration.resource &&
          Mcp::Configuration.client_allowed?(credential.application&.uid)
        render json: { error: "invalid_target" }, status: :bad_request
      end
    end
end
