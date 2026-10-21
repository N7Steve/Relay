class Oauth::AuthorizationsController < Doorkeeper::AuthorizationsController
  before_action :validate_mcp_resource, only: [ :new, :create ]
  before_action :default_application_scope, only: [ :new, :create ]

  private

    def validate_mcp_resource
      params.delete(:mcp_resource)
      return unless params[:resource].present? || Mcp::Configuration.client_allowed?(params[:client_id])

      unless Mcp::Configuration.enabled? && Mcp::Configuration.client_allowed?(params[:client_id]) &&
          params[:resource] == Mcp::Configuration.resource && params[:resource].present? &&
          params[:code_challenge_method] == "S256" && params[:code_challenge].present?
        return render json: { error: "invalid_target" }, status: :bad_request
      end
      params[:mcp_resource] = Mcp::Configuration.resource
    end

    def default_application_scope
      return if params[:scope].present?

      application = Doorkeeper::Application.find_by(uid: params[:client_id])
      params[:scope] = "read_write" if application&.scopes.to_s.split == [ "read_write" ]
    end
end
