# frozen_string_literal: true

class Api::V1::ContextController < Api::V1::BaseController
  before_action :ensure_read_scope

  def show
    render json: {
      api_version: "v1",
      user: { id: current_resource_owner.id, role: current_resource_owner.role },
      family: { id: current_resource_owner.family.id, currency: current_resource_owner.family.currency, timezone: Time.zone.name },
      authentication: { method: @authentication_method, scopes: current_scopes },
      capabilities: {
        read: api_access.readable?,
        write: api_access.writable?,
        manage_family: api_access.family_admin? && api_access.writable?,
        read_family_operations: api_access.family_admin?,
        read_family_insights: api_access.complete_account_visibility? && current_resource_owner.preview_features_enabled?,
        preview_features: current_resource_owner.preview_features_enabled?,
        mcp: Mcp::Configuration.enabled?
      },
      contracts: {
        account_permissions: "Account read_write permits annotations only; financial writes require owner or full_control",
        money: "Decimal strings or currency minor units; positive ledger amounts are outflows",
        dates: "ISO 8601 YYYY-MM-DD in family timezone",
        idempotency: "Transaction create: account_id, source and external_id identify the original entry"
      }
    }
  end
end
