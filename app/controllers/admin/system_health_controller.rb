# frozen_string_literal: true

module Admin
  class SystemHealthController < Admin::BaseController
    before_action :require_hosted_push, only: :send_test_push

    # Bypass the per-request memo / cross-request cache that the layout
    # banner uses. An operator landing on this page (often right after
    # restarting the worker) wants to confirm the current state, not a
    # snapshot up to `SidekiqHealth::CACHE_TTL` old.
    def show
      tabs = %w[background_jobs]
      @active_tab = params[:tab].presence_in(tabs) || "background_jobs"
      if Apns::Client.hosted?
        @push_notification_test = PushNotificationTest.new(Current.user)
        @push_disabled_reason = @push_notification_test.disabled_reason
        @latest_push_test = @push_notification_test.latest
        @push_test_results = @latest_push_test ? @push_notification_test.results(@latest_push_test) : []
      end
      SidekiqHealth.expire_cache!
      @health = SidekiqHealth.new
    end

    def send_test_push
      result = PushNotificationTest.new(Current.user).request!
      flash[result == :queued ? :notice : :alert] = t("admin.system_health.push_notifications.messages.#{result}")
      redirect_to admin_system_health_path(tab: "background_jobs", anchor: "push-notifications"), status: :see_other
    end

    private
      def require_hosted_push
        head :not_found unless Apns::Client.hosted?
      end
  end
end
