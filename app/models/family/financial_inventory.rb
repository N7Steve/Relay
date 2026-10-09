# Read-only preflight for an ISOLATED copy. Returns aggregate counts only; no
# names, amounts, account identifiers, metadata payloads or credentials leave it.
class Family::FinancialInventory
  CONFLICTING_PENDING_SQL = <<~SQL.squish.freeze
    EXISTS (SELECT 1 FROM jsonb_each(transactions.extra) namespace WHERE namespace.key IN (:providers) AND namespace.value ->> 'pending' = 'true')
    AND EXISTS (SELECT 1 FROM jsonb_each(transactions.extra) namespace WHERE namespace.key IN (:providers) AND namespace.value ->> 'pending' = 'false')
  SQL
  def initialize(family)
    @family = family
  end

  def call
    connection = ActiveRecord::Base.connection
    connection.transaction do
      # PostgreSQL enforces this even if a future query accidentally writes.
      connection.execute("SET TRANSACTION READ ONLY") unless connection.transaction_open? && Rails.env.test?
      entries = @family.entries
      transactions = @family.transactions
      {
        accounts_by_type: @family.accounts.group(:accountable_type).count,
        legacy_financial_treatment: legacy_count(@family.accounts, :financial_treatment),
        inconsistent_account_boundary: @family.accounts.where(cashflow_boundary: true, exclude_from_reports: false).count,
        investments_by_subtype: @family.accounts.where(accountable_type: "Investment").group("investments.subtype").joins("JOIN investments ON investments.id = accounts.accountable_id").count,
        legacy_posting_status: legacy_count(transactions, :posting_status),
        pending_transactions: transactions.where(Transaction::PENDING_CHECK_SQL.gsub("t.extra", "transactions.extra")).count,
        legacy_one_time: transactions.where(kind: "one_time").count,
        implicit_import_protection: legacy_count(entries.where(excluded: true), :import_protected),
        duplicate_entryables: entries.group(:entryable_type, :entryable_id).having("COUNT(*) > 1").count.size,
        orphan_entryables: entries.where(<<~SQL.squish).count,
          (entryable_type = 'Transaction' AND NOT EXISTS (SELECT 1 FROM transactions WHERE transactions.id = entries.entryable_id)) OR
          (entryable_type = 'Trade' AND NOT EXISTS (SELECT 1 FROM trades WHERE trades.id = entries.entryable_id)) OR
          (entryable_type = 'Valuation' AND NOT EXISTS (SELECT 1 FROM valuations WHERE valuations.id = entries.entryable_id))
        SQL
        transfer_legs_reused_across_roles: reused_transfer_leg_count,
        conflicting_pending_flags: transactions.where(CONFLICTING_PENDING_SQL, providers: Transaction::PENDING_PROVIDERS).count
      }
    end
  end

  private

    def legacy_count(scope, column)
      scope.klass.column_names.include?(column.to_s) ? scope.where(column => nil).count : scope.count
    end

    def reused_transfer_leg_count
      ids = @family.transactions.select(:id)
      Transfer.where(inflow_transaction_id: ids).where(outflow_transaction_id: Transfer.select(:inflow_transaction_id)).count
    end
end
