# frozen_string_literal: true

# Shared authorization vocabulary for API clients and the future MCP adapter.
# Token scopes restrict the actor; they never grant access to another account.
class Api::Access
  Forbidden = Class.new(StandardError)

  attr_reader :user, :scopes

  def initialize(user:, scopes:, credential: nil)
    @user = user
    @scopes = scopes.map(&:to_s)
    @credential = credential
  end

  def delegated_authority
    { "user_id" => user.id, "family_id" => user.family_id,
      "credential_type" => @credential&.class&.name, "credential_id" => @credential&.id }
  end

  def credential_label
    @credential.is_a?(ApiKey) ? @credential.name : @credential&.application&.name || "MCP"
  end

  def self.from_delegation!(authority, family:)
    actor = User.find_by(id: authority.fetch("user_id"), family_id: family.id)
    raise Forbidden, "Delegated actor is unavailable" unless actor && actor.family_id == authority["family_id"]
    credential = case authority["credential_type"]
    when "ApiKey" then actor.api_keys.active.find_by(id: authority["credential_id"])
    when "Doorkeeper::AccessToken"
      token = Doorkeeper::AccessToken.find_by(id: authority["credential_id"], resource_owner_id: actor.id)
      token if token&.accessible? && (token.mcp_resource.blank? || (Mcp::Configuration.enabled? && token.mcp_resource == Mcp::Configuration.resource && Mcp::Configuration.client_allowed?(token.application&.uid)))
    end
    raise Forbidden, "Delegated credential was revoked or expired" unless credential
    access = new(user: actor, scopes: credential.scopes.to_a, credential: credential)
    raise Forbidden, "Delegated authority changed: write scope or actor activity" unless access.writable?
    access
  end

  def readable?
    user.active? && (scopes & %w[read read_write]).any?
  end

  def writable?
    readable? && scopes.include?("read_write")
  end

  def accounts
    readable? ? user.family.accounts.accessible_by(user) : user.family.accounts.none
  end

  def allowed?(account, action)
    return false unless readable? && account.family_id == user.family_id

    permission = account.owner_id == user.id ? :owner : share_permissions[account.id]&.to_sym
    case action.to_sym
    when :read then permission.present?
    when :annotate then writable? && (permission == :owner || permission.to_s.in?(AccountShare::ANNOTATE_PERMISSIONS))
    when :write then writable? && permission.in?([ :owner, :full_control ])
    else false
    end
  end

  def require_account!(account, action)
    raise Forbidden, "Account permission does not allow this operation" unless allowed?(account, action)
  end

  # Family-wide imports, connections and syncs cannot be scoped to just one
  # shared account. The existing settings UI reserves provider management to admins.
  def family_admin?
    readable? && user.admin?
  end

  def complete_account_visibility?
    readable? && !user.family.accounts.where.not(id: accounts.select(:id)).exists?
  end

  def account_capabilities(account)
    { read: allowed?(account, :read), annotate: allowed?(account, :annotate), write: allowed?(account, :write) }
  end

  private
    def share_permissions
      @share_permissions ||= user.account_shares.pluck(:account_id, :permission).to_h
    end
end
