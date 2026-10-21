# frozen_string_literal: true

module Api::ParityOperations
  def get_capabilities(_args)
    { tools: Mcp::Catalog.all.values.select { |tool| access.writable? || tool[:annotations][:readOnlyHint] }.map { |tool| tool[:name] },
      permissions_rechecked_on_every_call: true, family_admin: access.family_admin?, instance_admin: user.super_admin?,
      complete_account_visibility: access.complete_account_visibility?, preview_features: user.preview_features_enabled?,
      coverage: "docs/research/relay-api-mcp-coverage.yml", external_access: get_external_access({}),
      human_presence: "Use get_human_flow for MFA, WebAuthn, consent, credential issuance and destructive identity operations" }
  end

  def get_transaction(args)
    entry_json(transaction_entry(args.fetch("transaction_id"), :read))
  end

  def list_transfers(args)
    paginate(readable_transfers.order(created_at: :desc, id: :asc), args) { |row| transfer_json(row) }
  end

  def get_transfer(args)
    transfer_json(readable_transfers.find(args.fetch("transfer_id")))
  end

  def list_rejected_transfers(args)
    scope = RejectedTransfer.where(outflow_transaction_id: entries.select(:entryable_id), inflow_transaction_id: entries.select(:entryable_id))
    paginate(scope.order(:id), args) { |row| row.attributes.slice("id", "outflow_transaction_id", "inflow_transaction_id") }
  end

  def list_local_securities(args)
    paginate(accessible_securities.order(:ticker, :id), args) { |row| security_json(row) }
  end

  def get_local_security(args)
    security_json(accessible_securities.find(args.fetch("security_id")))
  end

  def refresh_insights(_args)
    require_insight_authority!
    ApiIntegrationJob.perform_later("insights", family, access.delegated_authority)
    { queued: true }
  end

  private
    def readable_transfers
      Transfer.where(outflow_transaction_id: entries.select(:entryable_id), inflow_transaction_id: entries.select(:entryable_id))
    end

    def accessible_securities
      Security.where(id: family.holdings.where(account_id: access.accounts.select(:id)).select(:security_id)).or(
        Security.where(id: family.trades.joins(:entry).where(entries: { account_id: access.accounts.select(:id) }).select(:security_id)))
    end

    def security_json(row)
      row.attributes.slice("id", "name", "ticker", "exchange_operating_mic", "country_code", "kind")
    end

    def require_insight_authority!
      raise Api::Access::Forbidden, "Preview and complete account visibility required" unless user.preview_features_enabled? && access.complete_account_visibility?
    end
end
