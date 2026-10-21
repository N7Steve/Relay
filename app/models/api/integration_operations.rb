# frozen_string_literal: true

module Api::IntegrationOperations
  def list_bank_connections(args)
    paginate(family.enable_banking_items.ordered, args) { |row| bank_json(row) }
  end

  def get_bank_connection(args)
    bank_json(integration_bank(args))
  end

  def list_bank_accounts(args)
    paginate(integration_bank(args).enable_banking_accounts.order(:id), args) do |row|
      { id: row.id, name: row.name, currency: row.currency, account_id: row.account&.id, linked: row.account_provider.present? }
    end
  end

  def setup_bank_account(args)
    item = integration_bank(args)
    source = item.enable_banking_accounts.find(args.fetch("bank_account_id"))
    source.with_lock do
      invalid!("Bank account is already linked") if source.account_provider
      validate_accountable_attributes!(args.fetch("accountable_type"), { "subtype" => args["subtype"] }) if args["subtype"]
      record = Account.create_from_enable_banking_account(source, args.fetch("accountable_type"), args["subtype"], owner: user)
      AccountProvider.create!(account: record, provider: source)
      item.update!(pending_account_setup: false) unless item.enable_banking_accounts.left_joins(:account_provider).where(account_providers: { id: nil }).exists?
      account_json(record)
    end
  end

  def link_bank_account(args)
    source = integration_bank(args).enable_banking_accounts.find(args.fetch("bank_account_id"))
    record = account(args.fetch("account_id"), :write)
    source.with_lock do
      invalid!("Both accounts must be unlinked; unlink explicitly before moving history") if source.account_provider || record.account_providers.exists?
      AccountProvider.create!(account: record, provider: source)
    end
    account_json(record.reload)
  end

  def update_bank_connection(args)
    row = integration_bank(args)
    row.update!(args.slice("name", "sync_start_date"))
    bank_json(row)
  end

  def sync_bank(args)
    ExternalAccess.require!(:bank_sync)
    delegated_sync(integration_bank(args), "bank")
  end

  def sync_family(_args)
    delegated_sync(family, "family")
  end

  def recalculate_account(args)
    delegated_sync(account(args.fetch("account_id"), :write), "account")
  end

  def list_syncs(args)
    scope = integration_syncs
    scope = scope.where(syncable_type: "Account", syncable_id: args["account_id"]) if args["account_id"]
    paginate(scope.ordered, args) { |row| sync_json(row) }
  end

  def get_sync(args)
    sync_json(integration_syncs.find(args.fetch("sync_id")))
  end

  def cancel_sync(args)
    row = integration_syncs.find(args.fetch("sync_id"))
    row.syncable.is_a?(Account) ? access.require_account!(row.syncable, :write) : require_process_admin!
    { accepted: row.request_cancel!, sync: sync_json(row.reload) }
  end

  def get_drive_connection(_args)
    row = user.google_drive_connection
    { connected: row&.connected? || false, external_access: ExternalAccess.enabled?(:google_drive), connection: row&.attributes&.slice("id", "email", "status", "connected_at") }
  end

  def disconnect_drive(_args)
    row = user.google_drive_connection
    if row
      begin
        GoogleDrive::Client.revoke(token: row.refresh_token) if ExternalAccess.enabled?(:google_drive)
      rescue GoogleDrive::Client::Error => error
        DebugLogEntry.capture(category: "provider_auth", level: "warn", message: "Drive remote revocation failed: #{error.class}", source: self.class.name,
          family: family, user: user, provider_key: "google_drive")
      end
      row.destroy!
    end
    { disconnected: true }
  end

  def list_drive_schedules(args)
    paginate(user.google_drive_export_schedules.where(family: family).order(:id), args) { |row| drive_schedule_json(row) }
  end

  def get_drive_schedule(args)
    drive_schedule_json(integration_schedule(args))
  end

  def create_drive_schedule(args)
    connection = user.google_drive_connection
    invalid!("Connect Drive in the browser first") unless connection&.connected?
    row = connection.export_schedules.new(drive_schedule_attributes(args).merge(user: user, family: family))
    row.save!
    # Creating a recurring export explicitly establishes its native authorization;
    # immediate execution remains a separate operation.
    drive_schedule_json(row)
  end

  def update_drive_schedule(args)
    row = integration_schedule(args)
    row.assign_attributes(drive_schedule_attributes(args))
    row.next_run_at = row.next_occurrence_after(Time.current) if row.valid?
    row.save!
    drive_schedule_json(row)
  end

  def delete_drive_schedule(args)
    integration_schedule(args).destroy!
    { deleted: true }
  end

  def run_drive_export(args)
    ExternalAccess.require!(:google_drive)
    row = integration_schedule(args)
    invalid!("Schedule is not valid") unless row.valid?
    ApiIntegrationJob.perform_later("drive", row, access.delegated_authority)
    { schedule_id: row.id, queued: true }
  end

  def list_drive_runs(args)
    paginate(integration_schedule(args).runs.order(created_at: :desc, id: :asc), args) do |row|
      row.attributes.slice("id", "status", "triggered_by", "started_at", "finished_at", "record_count", "error_code")
    end
  end

  private
    def authorize_integration_arguments!(name, args)
      return unless Mcp::IntegrationCatalog.definitions.any? { |tool| tool[:name] == name }
      require_process_admin! if name.include?("bank") || name == "sync_family"
      integration_schedule(args) if args["schedule_id"]
      integration_bank(args) if args["bank_item_id"]
    end

    def integration_bank(args)
      family.enable_banking_items.active.find(args.fetch("bank_item_id"))
    end

    def integration_schedule(args)
      user.google_drive_export_schedules.where(family: family).find(args.fetch("schedule_id"))
    end

    def bank_json(row)
      row.attributes.slice("id", "name", "country_code", "aspsp_name", "status", "session_expires_at", "pending_account_setup", "sync_start_date").merge(
        "credentials_configured" => row.credentials_configured?, "session_valid" => row.session_valid?, "linked_account_count" => row.linked_accounts_count)
    end

    def delegated_sync(record, type)
      record.with_lock do
        row = record.syncs.pending.where("created_at > ?", Sync::VISIBLE_FOR.ago).where(cancel_requested_at: nil).order(:created_at).first
        unless row
          row = record.syncs.create!
          ApiIntegrationJob.perform_later(type, row, access.delegated_authority)
        end
        sync_json(row)
      end
    end

    def integration_syncs
      scope = Sync.where(syncable_type: "Account", syncable_id: access.accounts.select(:id))
      if access.family_admin? && access.complete_account_visibility?
        scope = scope.or(Sync.where(syncable_type: "Family", syncable_id: family.id)).or(Sync.where(syncable_type: "EnableBankingItem", syncable_id: family.enable_banking_items.select(:id)))
      end
      scope
    end

    def sync_json(row)
      row.attributes.slice("id", "status", "syncable_type", "syncable_id", "created_at", "updated_at", "completed_at", "cancel_requested_at").merge("failed" => row.failed?, "error_details_path" => "/settings/providers")
    end

    def drive_schedule_attributes(args)
      attrs = args.except("idempotency_key", "schedule_id")
      if attrs["filters"]
        filters = attrs["filters"]
        ids = filters.fetch("account_ids")
        invalid!("Unavailable export accounts") unless access.accounts.where(id: ids).count == ids.size
        { "excluded_category_ids" => family.categories, "excluded_tag_ids" => family.tags }.each do |key, scope|
          values = filters.fetch(key, [])
          invalid!("Unavailable export filters") unless scope.where(id: values).count == values.size
        end
      end
      attrs
    end

    def drive_schedule_json(row)
      financial_json(row.attributes.slice("id", "name", "filename", "status", "frequency", "run_at", "weekday", "day_of_month", "timezone", "date_range", "fixed_start_date", "rolling_days", "filters", "next_run_at", "last_error_code"))
    end
end
