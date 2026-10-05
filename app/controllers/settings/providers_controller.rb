class Settings::ProvidersController < ApplicationController
  layout -> { turbo_frame_request? ? "turbo_rails/frame" : "settings" }

  before_action :ensure_admin, only: [ :show, :update, :sync_all, :sync, :connect_form ]
  before_action :set_encryption_warning_context, only: [ :show, :connect_form ]

  def show
    @breadcrumbs = [
      [ t("breadcrumbs.home"), root_path ],
      [ t("breadcrumbs.bank_sync"), nil ]
    ]

    prepare_show_context
  rescue ActiveRecord::Encryption::Errors::Configuration => e
    Rails.logger.error("Active Record Encryption not configured: #{e.message}")
    @encryption_error = true
  end


  def update
    redirect_to settings_providers_path, notice: t(".no_changes")
  end

  def sync_all
    family = Current.family
    now = Time.current

    updated_count = Family
      .where(id: family.id)
      .where("last_sync_all_attempted_at IS NULL OR last_sync_all_attempted_at <= ?", 30.seconds.ago)
      .update_all(last_sync_all_attempted_at: now, updated_at: now)

    if updated_count.zero?
      return redirect_to settings_providers_path, notice: t("settings.providers.sync_all_recently")
    end

    SyncAllProvidersJob.perform_later(family.id)
    redirect_to settings_providers_path, notice: t("settings.providers.sync_all_in_progress")
  end

  def sync
    provider_key  = params[:provider_key]
    syncable_type = PANEL_SYNCABLE_TYPES[provider_key]
    return redirect_to settings_providers_path unless syncable_type

    items = syncable_type.constantize.where(family: Current.family).syncable
    scheduled = items.reject(&:syncing?)
    scheduled.each(&:sync_later)

    notice_key = scheduled.any? ? "settings.providers.sync_provider_in_progress" : "settings.providers.sync_provider_no_items"
    redirect_to settings_providers_path, notice: t(notice_key)
  end

  def connect_form
    provider_key = params[:provider_key]

    # Not FAMILY_PANELS_BY_KEY[provider_key]: Brakeman reads that as the param
    # choosing the partial to render.
    panel = FAMILY_PANELS.find { |p| p[:key] == provider_key }
    if panel
      @panel_key     = panel[:key]
      @panel_partial = panel[:partial]
      @panel_title   = panel[:title]
      load_provider_items(provider_key)
      return render :connect_form
    end

    redirect_to settings_providers_path, alert: t("settings.providers.not_found")
  rescue ActiveRecord::Encryption::Errors::Configuration
    redirect_to settings_providers_path, alert: t("settings.providers.encryption_error.title")
  end

  private

    def ensure_admin
      return if Current.user.admin?

      redirect_to root_path, alert: t("settings.providers.not_authorized")
    end

    def set_encryption_warning_context
      @provider_setup_encryption_warning = !ActiveRecordEncryptionConfig.explicitly_configured?
    end

    # Retained family-scoped connection management.
    FAMILY_PANELS = [
      { key: "enable_banking", title: "Enable Banking",  turbo_id: "enable_banking", partial: "enable_banking_panel" }
    ].freeze

    FAMILY_PANEL_KEYS = FAMILY_PANELS.map { |p| p[:key] }.freeze
    FAMILY_PANELS_BY_KEY = FAMILY_PANELS.index_by { |p| p[:key] }.freeze

    # Maps panel key → ActiveRecord model name for sync health queries
    PANEL_SYNCABLE_TYPES = {
      "enable_banking" => "EnableBankingItem"
    }.freeze

    def load_provider_items(provider_key)
      @enable_banking_items = Current.family.enable_banking_items.ordered if provider_key == "enable_banking"
    end

    # Prepares instance vars needed by the show view and partials
    def prepare_show_context
      @enable_banking_items = Current.family.enable_banking_items.ordered # Enable Banking panel needs session info for status display

      @provider_sync_health = compute_provider_sync_health(family_panel_items)

      entries = build_provider_entries

      @connected        = entries.select { |e| e[:summary][:status] == :ok }
      @needs_attention  = entries.select { |e| [ :warn, :err ].include?(e[:summary][:status]) }
      @available        = entries.select { |e| e[:summary][:status] == :off }
      @can_sync_all = (@connected + @needs_attention).any?

      @health = view_context.provider_health_strip(connected: @connected, needs_attention: @needs_attention)
    end

    # Maps each family panel key to the loaded item collection. Used by
    # compute_provider_sync_health and build_provider_entries to avoid relying
    # on instance_variable_get for control flow.
    def family_panel_items
      {
        "enable_banking" => @enable_banking_items
      }
    end

    # Returns a hash mapping provider key → { error:, last_synced_at:, stale: }
    # by querying the latest sync per item for each family panel provider.
    def compute_provider_sync_health(items_map)
      PANEL_SYNCABLE_TYPES.each_with_object({}) do |(key, syncable_type), health|
        ids = items_map[key]&.map(&:id)&.compact
        next if ids.blank?

        health[key] = sync_health_for(syncable_type, ids)
      end
    end

    # Determines error/stale status and last successful sync time for a set of items.
    def sync_health_for(syncable_type, item_ids)
      # Use window function to get the single latest sync per item (same pattern as ProviderConnectionStatus)
      ranked_subq = Sync
        .where(syncable_type: syncable_type, syncable_id: item_ids)
        .select("syncs.*, ROW_NUMBER() OVER (PARTITION BY syncable_id ORDER BY created_at DESC, id DESC) AS sync_rank")

      latest_per_item = Sync.from(ranked_subq, :syncs).where("sync_rank = 1").to_a

      has_error = latest_per_item.any? { |s| s.failed? || s.stale? }

      last_synced = Sync
        .where(syncable_type: syncable_type, syncable_id: item_ids, status: "completed")
        .maximum(:completed_at)

      stale = !has_error && last_synced.present? && last_synced < 24.hours.ago

      { error: has_error, last_synced_at: last_synced, stale: stale }
    end

    # Builds retained connection summaries for the settings page.
    def build_provider_entries
      FAMILY_PANELS.map do |panel|
        {
          provider_key: panel[:key],
          title: panel[:title],
          turbo_id: panel[:turbo_id],
          partial: panel[:partial],
          auto_open_param: panel[:auto_open],
          maturity: Provider::Metadata.for(panel[:key])[:maturity],
          summary: view_context.provider_summary(panel[:key])
        }
      end.sort_by { |entry| entry[:title].downcase }
    end
end
