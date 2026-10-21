# frozen_string_literal: true

syncable = sync.syncable

json.id sync.id
json.status sync.status
json.in_progress sync.in_progress?
json.terminal sync.terminal?
json.syncable do
  json.type sync.syncable_type
  json.id sync.syncable_id
  json.name syncable&.try(:name)
end
json.parent_id(api_access.family_admin? ? sync.parent_id : nil)
json.children_count(api_access.family_admin? ? sync.children.size : sync.children.where(syncable_type: "Account", syncable_id: api_access.accounts.select(:id)).count)
json.window_start_date sync.window_start_date
json.window_end_date sync.window_end_date
json.pending_at sync.pending_at
json.syncing_at sync.syncing_at
json.completed_at sync.completed_at
json.failed_at sync.failed_at
json.error sync.api_error_payload
json.created_at sync.created_at
json.updated_at sync.updated_at
