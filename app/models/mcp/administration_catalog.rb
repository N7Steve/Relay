# frozen_string_literal: true

class Mcp::AdministrationCatalog
  def self.definitions
    c = Mcp::Catalog
    preview = { preview_token: { type: "string", maxLength: 16000 } }
    changes = { account_id: c::ID, user_id: c::ID, permission: { type: [ "string", "null" ], enum: [ nil, "full_control", "read_write", "read_only" ] }, role: { type: "string", enum: %w[guest member admin] } }
    actions = %w[update_account_share update_budget_share update_member_role delete_account unlink_account disconnect_bank]
    preferences = { show_sidebar: c::BOOLEAN, default_period: c::STRING, default_account_order: c::STRING, theme: { type: "string", enum: User::THEMES }, preview_features_enabled: c::BOOLEAN }
    family_attrs = { name: c::STRING, currency: c::STRING, country: c::STRING, date_format: c::STRING, timezone: c::STRING, locale: c::STRING,
      month_start_day: { type: "integer", minimum: 1, maximum: 28 }, personal_budgets: c::BOOLEAN, household_budget_enabled: c::BOOLEAN,
      moniker: { type: "string", enum: Family::MONIKERS }, default_account_sharing: { type: "string", enum: Family::SHARING_DEFAULTS }, enabled_currencies: { type: "array", maxItems: 100, items: c::STRING } }
    settings = %i[external_bank_sync_enabled external_google_drive_enabled external_logos_enabled require_email_confirmation auto_sync_enabled].to_h { |key| [ key, c::BOOLEAN ] }.merge(auto_sync_time: c::STRING, auto_sync_timezone: c::STRING)
    tools = [
      c.definition("get_profile", {}, read: true),
      c.definition("update_profile", { first_name: c::STRING, last_name: c::STRING, locale: c::STRING }),
      c.definition("get_preferences", {}, read: true),
      c.definition("update_preferences", preferences),
      c.definition("get_family_settings", {}, read: true),
      c.definition("update_family_settings", family_attrs),
      c.definition("list_members", c::PAGE, read: true),
      c.definition("list_invitations", c::PAGE, read: true),
      c.definition("create_invitation", { email: c::STRING, role: { type: "string", enum: %w[member guest] } }, required: %w[email role]),
      c.definition("revoke_invitation", { invitation_id: c::ID }, required: [ "invitation_id" ]),
      c.definition("list_account_shares", { account_id: c::ID }.merge(c::PAGE), required: [ "account_id" ], read: true),
      c.definition("set_finance_inclusion", { account_id: c::ID, included: c::BOOLEAN }, required: %w[account_id included]),
      c.definition("list_budget_shares", c::PAGE, read: true),
      c.definition("preview_access_change", changes.merge(operation: { type: "string", enum: actions }, bank_item_id: c::ID), required: [ "operation" ], read: true),
      c.definition("list_sessions", c::PAGE, read: true),
      c.definition("revoke_session", { session_id: c::ID }, required: [ "session_id" ]),
      c.definition("list_api_keys", c::PAGE, read: true),
      c.definition("revoke_api_key", { api_key_id: c::ID }, required: [ "api_key_id" ]),
      c.definition("list_oauth_grants", c::PAGE, read: true),
      c.definition("revoke_oauth_grant", { application_id: c::STRING }, required: [ "application_id" ]),
      c.definition("get_security_status", {}, read: true),
      c.definition("get_human_flow", { flow: { type: "string", enum: %w[password email mfa passkeys sso api_key oauth_client member_removal family_reset instance_users instance_sso bank_credentials bank_authorization drive_authorization drive_credentials account_lifecycle] }, bank_item_id: c::ID, account_id: c::ID }, required: [ "flow" ], read: true),
      c.definition("get_external_access", {}, read: true),
      c.definition("get_instance_status", {}, read: true),
      c.definition("preview_instance_settings", settings, read: true),
      c.definition("update_instance_settings", settings.merge(preview), required: [ "preview_token" ]),
      c.definition("list_diagnostics", c::PAGE.merge(level: { type: "string", enum: DebugLogEntry::LEVELS }), read: true),
      c.definition("get_background_status", {}, read: true),
      c.definition("list_background_operations", c::PAGE, read: true),
      c.definition("cancel_background_operation", { kind: { type: "string", enum: %w[import session backup] }, record_id: c::ID }, required: %w[kind record_id]),
      c.definition("list_insights", c::PAGE, read: true),
      c.definition("set_insight_status", { insight_id: c::ID, status: { type: "string", enum: %w[read acknowledged unacknowledged] } }, required: %w[insight_id status]),
      c.definition("set_local_image", { kind: { type: "string", enum: %w[profile account merchant] }, account_id: c::ID, merchant_id: c::ID, upload_token: { type: [ "string", "null" ], maxLength: 4000 } }, required: %w[kind upload_token])
    ]
    actions.each do |operation|
      keys = case operation
      when "update_account_share" then %w[account_id user_id permission]
      when "update_budget_share" then %w[user_id permission]
      when "update_member_role" then %w[user_id role]
      when "disconnect_bank" then %w[bank_item_id]
      else [ "account_id" ]
      end
      tools << c.definition(operation, changes.merge(bank_item_id: c::ID).slice(*keys.map(&:to_sym)).merge(preview), required: keys + [ "preview_token" ], destructive: operation.in?(%w[delete_account disconnect_bank]))
    end
    tools
  end
end
