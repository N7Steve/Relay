module ExternalAccessGuardable
  extend ActiveSupport::Concern

  included do
    before_action :guard_external_connection
    rescue_from ExternalAccess::Disabled do
      head :forbidden
    end
    rescue_from Money::ConversionError, Security::Provided::SecurityInfoMissingError do |error|
      render_insufficient_financial_data(error)
    end
    rescue_from ActionView::Template::Error do |error|
      cause = error.cause
      raise error unless cause.is_a?(Money::ConversionError) || cause.is_a?(Security::Provided::SecurityInfoMissingError)

      render_insufficient_financial_data(cause)
    end
  end

  private
    def render_insufficient_financial_data(error)
      message = I18n.t("external_access.insufficient_data", details: error.message)
      if request.format.json?
        render json: { error: message }, status: :unprocessable_content
      else
        render plain: message, status: :unprocessable_content
      end
    end

    def guard_external_connection
      provider_controller = Family.reflect_on_all_associations(:has_many).any? do |association|
        association.name.to_s == controller_name && controller_name.end_with?("_items")
      end
      bank_webhook = controller_name == "webhooks"
      head :forbidden if (provider_controller || bank_webhook) && !ExternalAccess.enabled?(:bank_sync)
    end
end
