# The Family section: super admins see and operate on the accounts of the rest
# of their family without those accounts joining their own finances.
class FamilyAccountsController < ApplicationController
  before_action :require_family_manager!

  def show
    accounts = Current.user.family_managed_accounts
      .visible
      .includes(:accountable)
      .with_attached_logo
      .alphabetically
      .to_a

    @accounts_by_owner_id = accounts.group_by(&:owner_id)
    @members = Current.family.users.where.not(id: Current.user.id).to_a.sort_by { |user| user.display_name.downcase }
    @unowned_accounts = @accounts_by_owner_id.fetch(nil, [])
  end

  def update
    Current.user.update_show_family_accounts!(params[:show_family_accounts])

    redirect_to family_accounts_path, notice: t(".success")
  end

  private
    def require_family_manager!
      return if Current.user&.family_manager?

      redirect_to root_path, alert: t("family_accounts.not_authorized")
    end
end
