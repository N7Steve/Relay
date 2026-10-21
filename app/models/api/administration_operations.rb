# frozen_string_literal: true

module Api::AdministrationOperations
  INSTANCE_FIELDS = %w[external_bank_sync_enabled external_google_drive_enabled external_logos_enabled syncs_include_pending require_email_confirmation auto_sync_enabled auto_sync_time auto_sync_timezone].freeze

  def get_profile(_args)
    user.attributes.slice("id", "first_name", "last_name", "locale", "role", "active")
  end

  def update_profile(args)
    user.update!(args.slice("first_name", "last_name", "locale"))
    get_profile({})
  end

  def get_preferences(_args)
    user.attributes.slice("show_sidebar", "default_period", "default_account_order", "theme").merge("preview_features_enabled" => user.preview_features_enabled?)
  end

  def update_preferences(args)
    attrs = args.slice("show_sidebar", "default_period", "default_account_order", "theme")
    attrs["preferences"] = user.preferences.to_h.merge("preview_features_enabled" => args["preview_features_enabled"]) if args.key?("preview_features_enabled")
    user.update!(attrs)
    get_preferences({})
  end

  def get_family_settings(_args)
    family.attributes.slice("id", "name", "currency", "country", "date_format", "timezone", "locale", "month_start_day", "personal_budgets", "household_budget_enabled", "moniker", "default_account_sharing", "enabled_currencies")
  end

  def update_family_settings(args)
    values = args.except("idempotency_key")
    market_currency(values["currency"]) if values["currency"]
    Array(values["enabled_currencies"]).each { |value| market_currency(value) }
    family.update!(values)
    get_family_settings({})
  end

  def list_members(args)
    paginate(family.users.order(:id), args) { |row| row.attributes.slice("id", "first_name", "last_name", "role", "active") }
  end

  def list_invitations(args)
    paginate(family.invitations.pending.order(:id), args) { |row| row.attributes.slice("id", "email", "role", "expires_at", "accepted_at") }
  end

  def create_invitation(args)
    row = family.invitations.create!(inviter: user, email: args.fetch("email"), role: args.fetch("role"))
    row.attributes.slice("id", "email", "role", "expires_at").merge("delivery" => "Prepared only; share or send through the authenticated invitation page", "path" => "/settings/profile")
  end

  def revoke_invitation(args)
    family.invitations.pending.find(args.fetch("invitation_id")).destroy!
    { revoked: true }
  end

  def list_account_shares(args)
    row = account(args.fetch("account_id"))
    raise Api::Access::Forbidden, "Account owner required" unless row.owned_by?(user)
    paginate(row.account_shares.order(:id), args) { |share| share.attributes.slice("id", "user_id", "permission", "include_in_finances") }
  end

  def set_finance_inclusion(args)
    row = account(args.fetch("account_id"))
    invalid!("Owners already participate in their finances") if row.owned_by?(user)
    share = row.account_shares.find_by!(user: user)
    share.update!(include_in_finances: args.fetch("included"))
    { account_id: row.id, included: share.include_in_finances }
  end

  def list_budget_shares(args)
    paginate(user.budget_shares_given.order(:id), args) { |row| row.attributes.slice("id", "owner_id", "viewer_id", "permission") }
  end

  def preview_access_change(args)
    operation = args.fetch("operation")
    plan = access_change_plan(operation, args.except("operation"))
    { operation: operation, impact: plan[:impact], preview_token: process_preview(operation, plan[:id], plan[:fingerprint]), expires_in: 600 }
  end

  %w[update_account_share update_budget_share update_member_role delete_account unlink_account disconnect_bank].each do |operation|
    define_method(operation) do |args|
      plan = access_change_plan(operation, args, lock: true)
      verify_process_preview!(args, operation, plan[:id], plan[:fingerprint])
      row, target = plan.values_at(:record, :target)
      case operation
      when "update_account_share"
        share = row.account_shares.find_by(user: target)
        if args["permission"]
          share ||= row.account_shares.build(user: target, include_in_finances: true)
          share.update!(permission: args["permission"])
        else
          share&.destroy!
        end
      when "update_budget_share"
        invalid!("Invalid budget permission") if args["permission"] && !BudgetShare::PERMISSIONS.include?(args["permission"])
        share = user.budget_shares_given.find_by(viewer: target)
        if args["permission"]
          share ||= user.budget_shares_given.build(viewer: target)
          share.update!(permission: args["permission"])
        else
          share&.destroy!
        end
      when "update_member_role"
        invalid!("Super administrators must be managed in the authenticated instance console") if target.super_admin? || target == user
        target.update!(role: args.fetch("role"))
      when "delete_account"
        invalid!("Unlink the account before deleting it") if row.linked?
        row.destroy_later
      when "unlink_account"
        ids = row.account_providers.pluck(:id)
        Holding.where(account_provider_id: ids).update_all(account_provider_id: nil)
        row.account_providers.destroy_all
      when "disconnect_bank"
        result = row.unlink_all!(dry_run: false)
        invalid!("Unlink failed; no partial disconnect was committed") if result.any? { |item| item[:error] }
        row.revoke_session if ExternalAccess.enabled?(:bank_sync)
        row.destroy_later
      end
      DebugLogEntry.capture(category: "access_change", level: "info", message: "Delegated #{operation}", source: self.class.name,
        family: family, user: user, metadata: { record_id: plan[:id], target_user_id: target&.id })
      { completed: true, id: plan[:id] }
    end
  end

  def list_sessions(args)
    paginate(user.sessions.order(created_at: :desc, id: :asc), args) { |row| row.attributes.slice("id", "created_at", "updated_at") }
  end

  def revoke_session(args)
    user.sessions.find(args.fetch("session_id")).destroy!
    { revoked: true }
  end

  def list_api_keys(args)
    paginate(user.api_keys.active.order(:id), args) { |row| row.attributes.slice("id", "name", "scopes", "source", "expires_at", "last_used_at") }
  end

  def revoke_api_key(args)
    user.api_keys.find(args.fetch("api_key_id")).revoke!
    { revoked: true }
  end

  def list_oauth_grants(args)
    paginate(Doorkeeper::AccessToken.where(resource_owner_id: user.id, revoked_at: nil).order(:id), args) do |row|
      { id: row.id.to_s, application_id: row.application_id.to_s, name: row.application&.name, scopes: row.scopes.to_a, expires_in: row.expires_in, created_at: row.created_at }
    end
  end

  def revoke_oauth_grant(args)
    scope = Doorkeeper::AccessToken.where(resource_owner_id: user.id, application_id: args.fetch("application_id"))
    invalid!("No grant for this actor") unless scope.exists?
    scope.find_each(&:revoke)
    Doorkeeper::AccessGrant.where(resource_owner_id: user.id, application_id: args.fetch("application_id")).find_each(&:revoke)
    { revoked: true }
  end

  def get_security_status(_args)
    { mfa_enabled: user.otp_required?, passkey_count: user.webauthn_credentials.count, sso_identity_count: user.oidc_identities.count,
      sessions: user.sessions.count, active_api_keys: user.api_keys.active.count, sensitive_changes_require_browser: true }
  end

  def get_human_flow(args)
    flow = args.fetch("flow")
    path = case flow
    when "password" then "/password/edit"
    when "email", "member_removal", "family_reset" then "/settings/profile"
    when "mfa", "passkeys", "sso" then "/settings/security"
    when "api_key" then "/settings/api_keys/new"
    when "oauth_client" then "/oauth/applications"
    when "instance_users" then "/admin/users"
    when "instance_sso" then "/admin/sso_providers"
    when "bank_credentials" then "/settings/providers"
    when "bank_authorization"
      row = family.enable_banking_items.find(args.fetch("bank_item_id"))
      "/enable_banking_items/#{row.id}/select_bank"
    when "drive_authorization", "drive_credentials" then "/family_exports"
    when "account_lifecycle"
      invalid!("account_id is required") unless args["account_id"]
      "/accounts/#{account(args['account_id']).id}"
    end
    { flow: flow, path: path, human_required: true, method: "GET", reason: "Native authenticated browser flow preserves reauthentication, consent and secret issuance. An API credential does not provide human presence." }
  end

  def get_external_access(_args)
    ExternalAccess::CAPABILITIES.to_h do |key|
      [ key, { enabled: ExternalAccess.enabled?(key), configured: Setting.public_send("external_#{key}_enabled") == true,
        environment_override: key != :logos && ENV.key?("RELAY_EXTERNAL_#{key.to_s.upcase}_ENABLED") } ]
    end
  end

  def get_instance_status(_args)
    { mcp_enabled: Mcp::Configuration.enabled?, mcp_resource: Mcp::Configuration.enabled? ? Mcp::Configuration.resource : nil,
      external_access: get_external_access({}), settings: instance_settings, secret_values: "not exposed", host_administration: "outside API scope" }
  end

  def preview_instance_settings(args)
    values = args.except("idempotency_key", "preview_token")
    { changes: values, preview_token: process_preview("instance-settings", user.id, process_digest([ instance_settings, values ])), expires_in: 600 }
  end

  def update_instance_settings(args)
    ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(812948372)")
    values = args.except("idempotency_key", "preview_token")
    verify_process_preview!(args, "instance-settings", user.id, process_digest([ instance_settings, values ]))
    invalid!("Invalid auto sync time") if values["auto_sync_time"] && !Setting.valid_auto_sync_time?(values["auto_sync_time"])
    invalid!("Invalid auto sync timezone") if values["auto_sync_timezone"] && !Setting.valid_auto_sync_timezone?(values["auto_sync_timezone"])
    INSTANCE_FIELDS.each { |key| Setting.public_send("#{key}=", values[key]) if values.key?(key) }
    AutoSyncScheduler.sync! if values.keys.any? { |key| key.start_with?("auto_sync_") }
    get_instance_status({})
  end

  def list_diagnostics(args)
    scope = DebugLogEntry.where(family_id: family.id).order(created_at: :desc, id: :asc)
    scope = scope.where(level: args["level"]) if args["level"]
    paginate(scope, args) { |row| row.attributes.slice("id", "category", "level", "source", "provider_key", "created_at").merge("details_path" => "/settings/debug") }
  end

  def list_insights(args)
    paginate(family.insights.for_product_frontend.visible.ordered.order(:id), args) { |row| insight_json(row) }
  end

  def get_background_status(_args)
    console = BackgroundJobConsole.new
    { runtime_known: !console.redis_error?, scan_complete: !console.queue_scan_truncated?, stats: console.stats&.to_h,
      scope: "Runtime counts are instance-wide; operation records are limited to the actor family" }
  end

  def list_background_operations(args)
    rows = BackgroundJobConsole.new.operations.select { |row| BackgroundJobConsole.family_for(row)&.id == family.id }
    page, limit = args.fetch("page", 1), args.fetch("per_page", 25)
    { data: rows.slice((page - 1) * limit, limit).to_a.map { |row| { id: row.id, type: row.class.base_class.name, status: row.status, updated_at: row.updated_at } },
      pagination: { page: page, per_page: limit, total_count: rows.size, next_page: page * limit < rows.size ? page + 1 : nil },
      bounded: true, source_limit_per_type: BackgroundJobConsole::OPERATIONS_LIMIT }
  end

  def cancel_background_operation(args)
    row = case args.fetch("kind")
    when "import" then family.imports.find(args.fetch("record_id"))
    when "session" then family.import_sessions.find(args.fetch("record_id"))
    when "backup" then family.family_exports.find(args.fetch("record_id"))
    end
    invalid!("PDF history must be managed in its native browser flow") if row.is_a?(PdfImport)
    console = BackgroundJobConsole.new
    invalid!("Worker liveness is unknown, queued, running or too recent") unless console.cancellable?(row)
    row.with_lock do
      valid = case row
      when Import then row.importing? || row.reverting?
      when ImportSession then row.importing?
      when FamilyExport then row.pending? || row.processing?
      end
      invalid!("Operation changed since it was inspected") unless valid && row.updated_at <= BackgroundJobConsole::STUCK_AFTER.ago
      case row
      when Import
        if row.importing? && row.data_committed?
          row.update!(status: "complete")
        else
          row.update!(status: row.reverting? ? "revert_failed" : "failed", error: "Marked as lost by an authorized instance administrator")
        end
      when ImportSession
        row.reconcile_committed_chunks!
        row.update!(status: "failed", error_details: { "code" => "cancelled_by_admin" })
      when FamilyExport then row.update!(status: "failed")
      end
    end
    DebugLogEntry.capture(category: "background_jobs", level: "warn", message: "Delegated lost-operation recovery", source: self.class.name,
      family: family, user: user, metadata: { record_id: row.id, kind: args["kind"] })
    { id: row.id, status: row.status }
  end

  def set_insight_status(args)
    row = family.insights.for_product_frontend.find(args.fetch("insight_id"))
    case args.fetch("status")
    when "read" then row.mark_read!
    when "acknowledged" then row.acknowledge!
    when "unacknowledged" then row.unacknowledge!
    end
    insight_json(row)
  end

  def set_local_image(args)
    row = case args.fetch("kind")
    when "profile" then user
    when "account"
      invalid!("account_id required") unless args["account_id"]
      account(args.fetch("account_id"), :write)
    when "merchant"
      require_process_admin!
      invalid!("merchant_id required") unless args["merchant_id"]
      merchant = family.available_merchants_for(user).find(args["merchant_id"])
      family.merchant_customizations.find_or_initialize_by(merchant: merchant)
    end
    attachment = args["kind"] == "profile" ? row.profile_image : row.custom_logo
    if args["upload_token"]
      blob = upload_blob(args)
      invalid!("Image must be JPEG, PNG or WebP up to 5 MiB") unless blob.content_type.in?(%w[image/jpeg image/png image/webp]) && blob.byte_size <= 5.megabytes
      attachment.attach(blob)
      row.save!
    else
      attachment.purge_later
    end
    family.reset_account_custom_logos_cache! if row.is_a?(Account)
    family.reset_merchant_customizations_cache! if row.is_a?(MerchantCustomization)
    { attached: attachment.attached? }
  end

  private
    def authorize_administration_arguments!(name, args)
      return unless Mcp::AdministrationCatalog.definitions.any? { |tool| tool[:name] == name }
      require_instance_admin! if name.in?(%w[get_instance_status preview_instance_settings update_instance_settings list_diagnostics update_member_role get_background_status list_background_operations cancel_background_operation])
      require_process_admin! if name.in?(%w[list_background_operations cancel_background_operation])
      require_family_admin! if name.in?(%w[update_family_settings list_invitations create_invitation revoke_invitation])
      require_process_admin! if name == "set_local_image" && args["kind"] == "merchant"
      if name.in?(%w[list_insights set_insight_status])
        raise Api::Access::Forbidden, "Preview and complete account visibility required" unless user.preview_features_enabled? && access.complete_account_visibility?
      end
      if name == "get_human_flow"
        require_instance_admin! if args["flow"].in?(%w[instance_users instance_sso oauth_client])
        require_family_admin! if args["flow"].in?(%w[member_removal family_reset bank_credentials bank_authorization])
        invalid!("bank_item_id is required") if args["flow"] == "bank_authorization" && !args["bank_item_id"]
      end
      access_change_plan(name, args) if name.in?(%w[update_account_share update_budget_share update_member_role delete_account unlink_account disconnect_bank])
    end

    def require_family_admin!
      raise Api::Access::Forbidden, "Family administrator required" unless access.family_admin?
    end

    def require_instance_admin!
      raise Api::Access::Forbidden, "Instance super administrator required" unless user.super_admin?
    end

    def access_change_plan(operation, args, lock: false)
      require_process_admin! if operation == "delete_account"
      allowed = Mcp::AdministrationCatalog.definitions.find { |tool| tool[:name] == operation }.fetch(:inputSchema).fetch(:properties).keys.map(&:to_s) - %w[idempotency_key preview_token]
      invalid!("Fields do not belong to this access change") if (args.keys - allowed - %w[idempotency_key preview_token]).any?
      values = args.slice(*allowed)
      schema = Mcp::Catalog.fetch(operation).fetch(:inputSchema).deep_dup
      schema[:required] -= %w[idempotency_key preview_token]
      Mcp::Catalog.validate!(schema, values)
      record, target = nil, nil
      if operation.in?(%w[update_account_share delete_account unlink_account])
        invalid!("account_id is required") unless args["account_id"]
        record = account(args["account_id"], :read)
        required_permission = operation == "update_account_share" ? record.owned_by?(user) : access.allowed?(record, :write)
        raise Api::Access::Forbidden, "Account authority required" unless required_permission
      elsif operation == "update_budget_share"
        record = user
      elsif operation == "update_member_role"
        require_instance_admin!
        record = family
      elsif operation == "disconnect_bank"
        require_process_admin!
        invalid!("bank_item_id is required") unless args["bank_item_id"]
        record = family.enable_banking_items.find(args["bank_item_id"])
      else
        invalid!("Unknown access change")
      end
      if operation.in?(%w[update_account_share update_budget_share update_member_role])
        invalid!("user_id is required") unless args["user_id"]
        target = family.users.where(active: true).where.not(id: user.id).find(args["user_id"])
      end
      record.lock! if lock && record != user
      snapshots = [ record.attributes, target&.attributes&.slice("id", "role", "active", "updated_at") ]
      snapshots << record.account_shares.order(:id).map(&:attributes) if record.is_a?(Account)
      snapshots << record.entries.order(:id).map(&:attributes) if operation.in?(%w[delete_account unlink_account])
      snapshots << record.account_providers.order(:id).map(&:attributes) if record.is_a?(Account)
      snapshots << user.budget_shares_given.order(:id).map(&:attributes) if operation == "update_budget_share"
      snapshots << record.enable_banking_accounts.order(:id).map { |row| [ row.id, row.account_provider&.attributes ] } if operation == "disconnect_bank"
      { record: record, target: target, id: record.id, fingerprint: process_digest([ operation, Api::Operation.canonical(values), snapshots ]),
        impact: { record_id: record.id, target_user_id: target&.id, permission: args["permission"], role: args["role"], entries: record.is_a?(Account) ? record.entries.count : nil,
          note: operation == "delete_account" ? "Deletes account history, positions and goal links; native transfer and Agenda cleanup can affect other accounts. Complete family authority is required." : nil } }
    end

    def instance_settings
      INSTANCE_FIELDS.to_h { |key| [ key, Setting.public_send(key) ] }
    end

    def insight_json(row)
      financial_json(row.attributes.slice("id", "insight_type", "title", "body", "status", "priority", "generated_at", "read_at", "dismissed_at"))
    end
end
