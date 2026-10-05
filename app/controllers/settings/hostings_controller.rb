class Settings::HostingsController < ApplicationController
  layout "settings"

  guard_feature unless: -> { self_hosted? }

  before_action :ensure_admin, only: [ :update, :clear_cache ]
  before_action :ensure_super_admin_for_onboarding, only: :update

  def show
    @breadcrumbs = [
      [ t("breadcrumbs.home"), root_path ],
      [ t("breadcrumbs.self_hosting"), nil ]
    ]
  end

  def update
    if hosting_params.key?(:onboarding_state)
      onboarding_state = hosting_params[:onboarding_state].to_s
      Setting.onboarding_state = onboarding_state
    end

    if hosting_params.key?(:require_email_confirmation)
      Setting.require_email_confirmation = hosting_params[:require_email_confirmation]
    end

    if hosting_params.key?(:invite_only_default_family_id)
      value = hosting_params[:invite_only_default_family_id].presence
      Setting.invite_only_default_family_id = value
    end

    if hosting_params.key?(:external_logos_enabled)
      Setting.external_logos_enabled = hosting_params[:external_logos_enabled] == "1"
    end

    if hosting_params.key?(:brand_fetch_client_id)
      Setting.brand_fetch_client_id = hosting_params[:brand_fetch_client_id]
    end

    if hosting_params.key?(:brand_fetch_high_res_logos)
      Setting.brand_fetch_high_res_logos = hosting_params[:brand_fetch_high_res_logos] == "1"
    end

    if hosting_params.key?(:syncs_include_pending)
      Setting.syncs_include_pending = hosting_params[:syncs_include_pending] == "1"
    end

    sync_settings_changed = false

    if hosting_params.key?(:auto_sync_enabled)
      Setting.auto_sync_enabled = hosting_params[:auto_sync_enabled] == "1"
      sync_settings_changed = true
    end

    if hosting_params.key?(:auto_sync_time)
      time_value = hosting_params[:auto_sync_time]
      unless Setting.valid_auto_sync_time?(time_value)
        flash[:alert] = t(".invalid_sync_time")
        return redirect_to settings_hosting_path
      end

      Setting.auto_sync_time = time_value
      Setting.auto_sync_timezone = current_user_timezone
      sync_settings_changed = true
    end

    if sync_settings_changed
      sync_auto_sync_scheduler!
    end

    redirect_to settings_hosting_path, notice: t(".success")
  rescue Setting::ValidationError => error
    flash.now[:alert] = error.message
    render :show, status: :unprocessable_entity
  end

  def clear_cache
    DataCacheClearJob.perform_later(Current.family)
    redirect_to settings_hosting_path, notice: t(".cache_cleared")
  end


  private
    # Strong parameters for the self-hosting settings form.
    def hosting_params
      return ActionController::Parameters.new unless params.key?(:setting)
      permitted = params.require(:setting).permit(:onboarding_state, :require_email_confirmation, :invite_only_default_family_id, :external_logos_enabled, :brand_fetch_client_id, :brand_fetch_high_res_logos, :syncs_include_pending, :auto_sync_enabled, :auto_sync_time)
      permitted
    end

    def ensure_admin
      redirect_to settings_hosting_path, alert: t(".not_authorized") unless Current.user.admin?
    end

    def ensure_super_admin_for_onboarding
      onboarding_params = %i[onboarding_state invite_only_default_family_id]
      return unless onboarding_params.any? { |p| hosting_params.key?(p) }
      redirect_to settings_hosting_path, alert: t(".not_authorized") unless Current.user.super_admin?
    end

    def sync_auto_sync_scheduler!
      AutoSyncScheduler.sync!
    rescue StandardError => error
      Rails.logger.error("[AutoSyncScheduler] Failed to sync scheduler: #{error.message}")
      Rails.logger.error(error.backtrace.join("\n"))
      flash[:alert] = t(".scheduler_sync_failed")
    end

    def current_user_timezone
      Current.family&.timezone.presence || "UTC"
    end
end
