# frozen_string_literal: true

module Admin
  class SystemHealthController < Admin::BaseController
    # Bypass the per-request memo / cross-request cache that the layout
    # banner uses. An operator landing on this page (often right after
    # restarting the worker) wants to confirm the current state, not a
    # snapshot up to `SidekiqHealth::CACHE_TTL` old.
    def show
      tabs = %w[background_jobs]
      @active_tab = params[:tab].presence_in(tabs) || "background_jobs"
      SidekiqHealth.expire_cache!
      @health = SidekiqHealth.new
    end
  end
end
