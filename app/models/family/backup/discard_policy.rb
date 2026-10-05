# Wire-format policy for recovering the supported product from pre-pruning backups.
# This contains names only; it never loads retired models or writes their tables.
class Family::Backup::DiscardPolicy
  MODELS = %w[AkahuItem AkahuAccount BinanceItem BinanceAccount BrexItem BrexAccount CoinbaseItem CoinbaseAccount CoinspotItem CoinspotAccount CoinstatsItem CoinstatsAccount FinancekitItem FinancekitAccount FioItem FioAccount IbkrItem IbkrAccount IndexaCapitalItem IndexaCapitalAccount KrakenItem KrakenAccount LunchflowItem LunchflowAccount MercuryItem MercuryAccount MonobankItem MonobankAccount OnchainWalletItem OnchainWalletAccount PlaidItem PlaidAccount QuestradeItem QuestradeAccount RedbarkItem RedbarkAccount SimplefinItem SimplefinAccount SnaptradeItem SnaptradeAccount SophtronItem SophtronAccount TradeRepublicItem TradeRepublicAccount Trading212Item Trading212Account UpItem UpAccount WiseItem WiseAccount FinancekitAccountLineage FinancekitBatch FinancekitTransaction FinancekitBalanceObservation FinancekitConflict RecurringTransaction RecurrenceRule RecurringOccurrence RecurringAllocation RecurringPriceChange RecurringMatchRejection Chat Message ToolCall CategorizationComparison LlmUsage Subscription ExchangeRatePair EvalDataset EvalResult EvalRun EvalSample].freeze
  ATTRIBUTES = {
    "Account" => %w[plaid_account_id simplefin_account_id],
    "Entry" => %w[plaid_id],
    "Family" => %w[ai_prompt_overrides assistant_type bills_feed_token categorization_confidence_threshold categorization_provider categorization_shadow_rate data_enrichment_enabled recurring_transactions_disabled stripe_customer_id vector_store_id],
    "User" => %w[ai_enabled show_ai_sidebar last_viewed_chat_id],
    "FamilyDocument" => %w[provider_file_id],
    "Security" => %w[price_provider offline_reason failed_fetch_at failed_fetch_count first_provider_price_on],
    "Property" => %w[avm_provider avm_last_synced_on]
  }.freeze

  def self.retired?(name)
    MODELS.include?(name)
  end

  def initialize(records, attachments)
    @records = records
    @attachments = attachments
    @discarded = Hash.new(0)
    @removed_attributes = Hash.new(0)
  end

  def apply!
    records_by_model = @records.group_by { |row| row.dig("data", "model") }
    links_by_account = records_by_model.fetch("AccountProvider", []).group_by { |row| row.dig("data", "attributes", "account_id") }
    balances_by_account = records_by_model.fetch("Balance", []).group_by { |row| row.dig("data", "attributes", "account_id") }
    managed_providers = records_by_model.fetch("IndexaCapitalAccount", []).index_by { |row| row.dig("data", "attributes", "id") }
    @records.each do |row|
      data = row.fetch("data")
      attrs = data.fetch("attributes")
      if discard_record?(data)
        @discarded[data["model"]] += 1
      end
      next unless data["model"] == "Account"

      links = links_by_account.fetch(attrs["id"], [])
      attrs["account_providers_count"] = links.count { |link| !self.class.retired?(link.dig("data", "attributes", "provider_type")) }
      if attrs["plaid_account_id"].present? || attrs["simplefin_account_id"].present? || links.any? { |link| self.class.retired?(link.dig("data", "attributes", "provider_type")) }
        attrs["reverse_balance_history"] = true
      end
      managed_link = links.find { |link| link.dig("data", "attributes", "provider_type") == "IndexaCapitalAccount" }
      if managed_link
        provider_id = managed_link.dig("data", "attributes", "provider_id")
        provider = managed_providers.fetch(provider_id) { raise Family::Backup::InvalidBackupError, "Missing managed portfolio data for account #{attrs['id']}" }
        attrs["managed_portfolio"] = true
        attrs["imported_performance"] = provider.dig("data", "attributes", "raw_payload", "performance_history") || {}
      end
      if links.any? { |link| link.dig("data", "attributes", "provider_type") == "IbkrAccount" }
        attrs["imported_balance_history"] = balances_by_account.fetch(attrs["id"], []).filter_map do |candidate|
          balance = candidate.dig("data", "attributes")
          next unless balance["currency"].to_s.upcase == attrs["currency"].to_s.upcase

          { "report_date" => balance["date"], "total" => balance["balance"], "currency" => balance["currency"] }
        end
      end
    end
    kept, dropped = @records.partition { |row| !discard_record?(row["data"]) }
    dropped_keys = dropped.map { |row| [ row.dig("data", "model"), row.dig("data", "attributes", "id") ] }.to_set
    @attachments = @attachments.reject do |row|
      data = row["data"]
      discarded = dropped_keys.include?([ data["model"], data["record_id"] ])
      @discarded["#{data['model']} attachments"] += 1 if discarded
      discarded
    end
    dropped_link_ids = dropped.filter_map { |row| row.dig("data", "attributes", "id") if row.dig("data", "model") == "AccountProvider" }.to_set
    kept.each do |row|
      data = row["data"]
      attrs = data["attributes"]
      (ATTRIBUTES[data["model"]] || []).each do |field|
        @removed_attributes["#{data['model']}.#{field}"] += 1 if attrs.key?(field)
        attrs.delete(field)
      end
      if data["model"] == "Holding" && dropped_link_ids.include?(attrs["account_provider_id"])
        attrs["account_provider_id"] = nil
        attrs["imported_snapshot"] = true
      end
    end
    [ kept, @attachments ]
  end

  def warnings
    return [] if @discarded.empty? && @removed_attributes.empty?

    [ { code: "retired_data_discarded", message: "Only the supported financial product will be restored. Data from retired modules is discarded.", details: { records: @discarded, attributes: @removed_attributes } } ]
  end

  private
    def discard_record?(data)
      return true if self.class.retired?(data["model"])

      attrs = data["attributes"]
      (data["model"] == "Insight" && attrs["insight_type"].in?(%w[cash_flow_warning subscription_audit])) ||
        (data["model"] == "AccountProvider" && self.class.retired?(attrs["provider_type"])) ||
        (data["model"] == "ImportSourceMapping" && (self.class.retired?(attrs["source_type"]) || self.class.retired?(attrs["target_type"])))
    end
end
