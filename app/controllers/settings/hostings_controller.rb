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

    # Determine which providers are currently selected
    exchange_rate_provider = ENV["EXCHANGE_RATE_PROVIDER"].presence || Setting.exchange_rate_provider
    enabled_securities = Setting.enabled_securities_providers

    # Show provider settings if used for FX or enabled for securities
    @show_twelve_data_settings = exchange_rate_provider == "twelve_data" || enabled_securities.include?("twelve_data")
    @show_yahoo_finance_settings = exchange_rate_provider == "yahoo_finance" || enabled_securities.include?("yahoo_finance")
    @show_tiingo_settings = enabled_securities.include?("tiingo")
    @show_eodhd_settings = enabled_securities.include?("eodhd")
    @show_alpha_vantage_settings = enabled_securities.include?("alpha_vantage")
    @show_mansa_settings = enabled_securities.include?("mansa")
    tinkoff_invest_checked = enabled_securities.include?("tinkoff_invest")
    tinkoff_invest_configured = ENV["TINKOFF_INVEST_API_KEY"].present? || Setting.tinkoff_invest_api_key.present?
    @show_tinkoff_invest_settings = tinkoff_invest_checked || enabled_securities.include?("moex_public") || tinkoff_invest_configured
    @tinkoff_invest_moex_only = @show_tinkoff_invest_settings && !tinkoff_invest_checked

    # Only fetch provider data if we're showing the section
    if @show_twelve_data_settings
      twelve_data_provider = Provider::Registry.get_provider(:twelve_data)
      @twelve_data_usage = twelve_data_provider&.usage
      @plan_restricted_securities = Current.family.securities_with_plan_restrictions(provider: "TwelveData")
    end

    if @show_yahoo_finance_settings
      @yahoo_finance_provider = Provider::Registry.get_provider(:yahoo_finance)
      @yahoo_finance_health_status = @yahoo_finance_provider&.health_status || :unknown
    end

    # Property valuation (AVM) providers â€” usage is shown against their tight
    # monthly request caps when a key is configured
    @rentcast_usage = Provider::Registry.get_provider(:rentcast)&.usage
    @realie_usage = Provider::Registry.get_provider(:realie)&.usage
  end

  def update
    if hosting_params.key?(:onboarding_state)
      onboarding_state = hosting_params[:onboarding_state].to_s
      Setting.onboarding_state = onboarding_state
    end

    if hosting_params.key?(:demo_family_refresh_enabled) || hosting_params.key?(:demo_family_refresh_family_id)
      unless Current.user.super_admin?
        return redirect_to settings_hosting_path, alert: t(".not_authorized")
      end
      if hosting_params.key?(:demo_family_refresh_family_id)
        family_id = hosting_params[:demo_family_refresh_family_id].presence
        demo_email = Rails.application.config_for(:demo).with_indifferent_access.fetch(:email)
        unless family_id.nil? || User.admin.exists?(family_id: family_id, email: demo_email) && !User.super_admin.exists?(family_id: family_id)
          raise Setting::ValidationError, t(".invalid_demo_family")
        end
        if family_id.nil? && Setting.demo_family_refresh_enabled && hosting_params[:demo_family_refresh_enabled] != "0"
          raise Setting::ValidationError, t(".select_demo_family")
        end
        Setting.demo_family_refresh_family_id = family_id
      end
      if hosting_params.key?(:demo_family_refresh_enabled)
        if hosting_params[:demo_family_refresh_enabled] == "1" && Setting.demo_family_refresh_family_id.blank?
          raise Setting::ValidationError, t(".select_demo_family")
        end
        Setting.demo_family_refresh_enabled = hosting_params[:demo_family_refresh_enabled] == "1"
      end
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

    update_encrypted_setting(:twelve_data_api_key)

    if hosting_params.key?(:exchange_rate_provider)
      Setting.exchange_rate_provider = hosting_params[:exchange_rate_provider]
    end

    if hosting_params.key?(:securities_provider)
      Setting.securities_provider = hosting_params[:securities_provider]
    end

    if hosting_params.key?(:securities_providers)
      new_providers = Array(hosting_params[:securities_providers]).reject(&:blank?) & Security.valid_price_providers
      old_providers = Setting.enabled_securities_providers

      Setting.securities_providers = new_providers.join(",")

      Setting.securities_provider = "" if new_providers.empty?

      # Mark securities linked to removed providers as offline so they aren't
      # silently queried against an incompatible fallback provider (e.g. MFAPI
      # scheme codes sent to TwelveData). The price_provider is preserved so
      # provider_status can report :provider_unavailable.
      removed = old_providers - new_providers
      removed.each do |removed_provider|
        Security.where(price_provider: removed_provider, offline: false)
                .in_batches.update_all(offline: true, offline_reason: "provider_disabled")
      end

      # Bring securities back online when their provider is re-enabled â€” but only
      # those that were taken offline by a provider toggle, not by health checks.
      added = new_providers - old_providers
      added.each do |added_provider|
        Security.where(price_provider: added_provider, offline: true, offline_reason: "provider_disabled")
                .in_batches.update_all(offline: false, offline_reason: nil, failed_fetch_count: 0, failed_fetch_at: nil)
      end
    end

    update_encrypted_setting(:tiingo_api_key)
    update_encrypted_setting(:eodhd_api_key)
    update_encrypted_setting(:alpha_vantage_api_key)
    update_encrypted_setting(:tinkoff_invest_api_key)
    update_encrypted_setting(:mansa_api_key)
    update_encrypted_setting(:rentcast_api_key)
    update_encrypted_setting(:realie_api_key)

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
      permitted = params.require(:setting).permit(:onboarding_state, :require_email_confirmation, :invite_only_default_family_id, :demo_family_refresh_enabled, :demo_family_refresh_family_id, :external_logos_enabled, :brand_fetch_client_id, :brand_fetch_high_res_logos, :twelve_data_api_key, :tiingo_api_key, :eodhd_api_key, :alpha_vantage_api_key, :tinkoff_invest_api_key, :mansa_api_key, :rentcast_api_key, :realie_api_key, :exchange_rate_provider, :securities_provider, :syncs_include_pending, :auto_sync_enabled, :auto_sync_time, securities_providers: [])
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

    def update_encrypted_setting(param_key)
      return unless hosting_params.key?(param_key)
      value = hosting_params[param_key].to_s.strip

      # "********" is the masked placeholder rendered for an existing key; it
      # means "leave the stored value untouched". A blank submission, however,
      # is an explicit request to clear the key, so persist nil in that case.
      return if value == "********"

      Setting.public_send(:"#{param_key}=", value.presence)
    end

    def current_user_timezone
      Current.family&.timezone.presence || "UTC"
    end
end
