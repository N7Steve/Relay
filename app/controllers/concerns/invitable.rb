module Invitable
  extend ActiveSupport::Concern

  included do
    helper_method :invite_code_required?
  end

  private
    def invite_code_required?
      return false if @invitation.present?
      Setting.onboarding_state == "invite_only" && Setting.invite_only_default_family_id.blank?
    end
end
