# Builds FinanceKit rows as an installation from before pruning phase 9F left them.
module HistoricalFinancekitHelper
  def create_historical_financekit_link(family: families(:dylan_family), user: users(:family_admin), account: accounts(:depository))
    item = FinancekitItem.create!(
      family: family, user: user, status: "active", consent: { "selected_source_account_ids" => [] },
      enrollment_id: SecureRandom.uuid, enrollment_digest: SecureRandom.hex(32), publisher_id: SecureRandom.uuid,
      stream_id: SecureRandom.uuid, credential_digest: SecureRandom.hex(32)
    )
    lineage = FinancekitAccountLineage.create!(family: family, account: account, account_origin: "linked")
    FinancekitAccount.create!(
      financekit_item: item, financekit_account_lineage: lineage, source_id: SecureRandom.uuid,
      accountable_type: account.accountable_type, subtype: "checking", currency: account.currency,
      ledger_timezone: "UTC", mapping_digest: SecureRandom.hex(32), name: account.name
    )
    AccountProvider.create!(account: account, provider: lineage)

    [ item, lineage ]
  end
end
