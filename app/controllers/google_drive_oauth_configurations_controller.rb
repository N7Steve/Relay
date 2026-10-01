class GoogleDriveOauthConfigurationsController < ApplicationController
  def update
    configuration = Current.user.google_drive_oauth_configuration ||
                    Current.user.build_google_drive_oauth_configuration(family: Current.family)

    if configuration.update_credentials(configuration_params)
      redirect_to family_exports_path, notice: t("google_drive_oauth_configurations.update.success")
    else
      redirect_to family_exports_path, alert: configuration.errors.full_messages.to_sentence
    end
  end

  private
    def configuration_params
      params.require(:google_drive_oauth_configuration).permit(:client_id, :client_secret)
    end
end
