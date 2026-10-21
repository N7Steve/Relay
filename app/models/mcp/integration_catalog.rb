# frozen_string_literal: true

class Mcp::IntegrationCatalog
  def self.definitions
    c = Mcp::Catalog
    bank = { bank_item_id: c::ID }
    schedule = { schedule_id: c::ID }
    attrs = { name: c::STRING, filename: c::STRING, status: { type: "string", enum: %w[active paused] },
      frequency: { type: "string", enum: GoogleDriveExportSchedule.frequencies.keys }, run_at: c::STRING,
      weekday: { type: "integer", minimum: 0, maximum: 6 }, day_of_month: { type: "integer", minimum: 1, maximum: 31 },
      timezone: c::STRING, date_range: { type: "string", enum: GoogleDriveExportSchedule.date_ranges.keys },
      fixed_start_date: c::DATE, rolling_days: { type: "integer", minimum: 1, maximum: 3650 },
      filters: { type: "object", additionalProperties: false, properties: {
        account_ids: c::IDS.merge(minItems: 1), excluded_category_ids: c::IDS, excluded_tag_ids: c::IDS,
        export_format: { type: "string", enum: GoogleDriveExportSchedule::EXPORT_FORMATS }, include_category: c::BOOLEAN, include_tags: c::BOOLEAN
      }, required: [ "account_ids" ] } }
    [
      c.definition("list_bank_connections", c::PAGE, read: true),
      c.definition("get_bank_connection", bank, required: [ "bank_item_id" ], read: true),
      c.definition("list_bank_accounts", bank.merge(c::PAGE), required: [ "bank_item_id" ], read: true),
      c.definition("setup_bank_account", bank.merge(bank_account_id: c::ID, accountable_type: { type: "string", enum: Accountable::TYPES }, subtype: c::STRING), required: %w[bank_item_id bank_account_id accountable_type]),
      c.definition("link_bank_account", bank.merge(bank_account_id: c::ID, account_id: c::ID), required: %w[bank_item_id bank_account_id account_id]),
      c.definition("update_bank_connection", bank.merge(name: c::STRING, sync_start_date: c::DATE), required: [ "bank_item_id" ]),
      c.definition("sync_bank", bank, required: [ "bank_item_id" ]),
      c.definition("sync_family", {}),
      c.definition("recalculate_account", { account_id: c::ID }, required: [ "account_id" ]),
      c.definition("list_syncs", c::PAGE.merge(account_id: c::ID), read: true),
      c.definition("get_sync", { sync_id: c::ID }, required: [ "sync_id" ], read: true),
      c.definition("cancel_sync", { sync_id: c::ID }, required: [ "sync_id" ]),
      c.definition("get_drive_connection", {}, read: true),
      c.definition("disconnect_drive", {}),
      c.definition("list_drive_schedules", c::PAGE, read: true),
      c.definition("get_drive_schedule", schedule, required: [ "schedule_id" ], read: true),
      c.definition("create_drive_schedule", attrs, required: %w[name filename frequency run_at timezone filters]),
      c.definition("update_drive_schedule", schedule.merge(attrs), required: [ "schedule_id" ]),
      c.definition("delete_drive_schedule", schedule, required: [ "schedule_id" ], destructive: true),
      c.definition("run_drive_export", schedule, required: [ "schedule_id" ]),
      c.definition("list_drive_runs", schedule.merge(c::PAGE), required: [ "schedule_id" ], read: true)
    ]
  end
end
