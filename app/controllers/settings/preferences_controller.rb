class Settings::PreferencesController < ApplicationController
  layout "settings"

  def show
    @user = Current.user
    load_budget_sharing
  end

  def update
    @user = Current.user
    user_params = params.permit(user: [ :preview_features_enabled, :mcp_custom_instructions ]).fetch(:user, {})

    saved = @user.with_lock do
      if user_params.key?(:preview_features_enabled)
        enabled = ActiveModel::Type::Boolean.new.cast(user_params[:preview_features_enabled])
        @user.preferences = @user.preferences.to_h.merge("preview_features_enabled" => enabled)
      end
      @user.update(user_params.slice(:mcp_custom_instructions))
    end

    if saved
      flash[:notice] = t(".mcp_instructions_saved") if user_params.key?(:mcp_custom_instructions)
      redirect_to settings_preferences_path
    else
      load_budget_sharing
      render :show, status: :unprocessable_entity
    end
  end

  private

    def load_budget_sharing
      @family_members = Current.family.users.where.not(id: @user.id).where(active: true)
      @budget_shares = @user.budget_shares_given.index_by(&:viewer_id)
    end
end
