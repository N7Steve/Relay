# frozen_string_literal: true

class Settings::PendingChangesController < ApplicationController
  layout "settings"
  before_action :set_change_set, only: %i[show approve reject]

  def index
    @change_sets = Mcp::ChangeSet.for_actor(Current.user).order(created_at: :desc).limit(50)
    @summary = Mcp::ChangeSet::Summary.new(change_sets: @change_sets, actor: Current.user)
  end

  def show
    @summary = Mcp::ChangeSet::Summary.new(change_sets: [ @change_set ], actor: Current.user)
  end

  def approve
    @change_set.approve!(actor: Current.user, token: params[:review_token])
    redirect_to settings_pending_change_path(@change_set), notice: t(".success")
  rescue Api::Access::Forbidden, Api::Input::Invalid => error
    redirect_to settings_pending_change_path(@change_set), alert: t("settings.pending_changes.review_failed", reason: error.message)
  end

  def reject
    @change_set.reject!(actor: Current.user, token: params[:review_token])
    redirect_to settings_pending_change_path(@change_set), notice: t(".success")
  rescue Api::Access::Forbidden, Api::Input::Invalid => error
    redirect_to settings_pending_change_path(@change_set), alert: t("settings.pending_changes.review_failed", reason: error.message)
  end

  private
    def set_change_set
      @change_set = Mcp::ChangeSet.for_actor(Current.user).find(params[:id])
    end
end
