class RemoveRetiredProductPersistence < ActiveRecord::Migration[8.1]
  TABLES = %w[akahu_items akahu_accounts binance_items binance_accounts brex_items brex_accounts coinbase_items coinbase_accounts coinspot_items coinspot_accounts coinstats_items coinstats_accounts financekit_items financekit_accounts fio_items fio_accounts ibkr_items ibkr_accounts indexa_capital_items indexa_capital_accounts kraken_items kraken_accounts lunchflow_items lunchflow_accounts mercury_items mercury_accounts monobank_items monobank_accounts onchain_wallet_items onchain_wallet_accounts plaid_items plaid_accounts questrade_items questrade_accounts redbark_items redbark_accounts simplefin_items simplefin_accounts snaptrade_items snaptrade_accounts sophtron_items sophtron_accounts trade_republic_items trade_republic_accounts trading212_items trading212_accounts up_items up_accounts wise_items wise_accounts financekit_account_lineages financekit_batches financekit_transactions financekit_balance_observations financekit_conflicts recurring_transactions recurrence_rules recurring_occurrences recurring_allocations recurring_price_changes recurring_match_rejections chats messages tool_calls categorization_comparisons llm_usages subscriptions exchange_rate_pairs eval_datasets eval_results eval_runs eval_samples].freeze
  COLUMNS = {
    "accounts" => %w[plaid_account_id simplefin_account_id],
    "entries" => %w[plaid_id],
    "families" => %w[ai_prompt_overrides assistant_type bills_feed_token categorization_confidence_threshold categorization_provider categorization_shadow_rate data_enrichment_enabled recurring_transactions_disabled stripe_customer_id vector_store_id],
    "users" => %w[ai_enabled show_ai_sidebar last_viewed_chat_id],
    "family_documents" => %w[provider_file_id],
    "securities" => %w[price_provider offline_reason failed_fetch_at failed_fetch_count first_provider_price_on]
  }.freeze
  SETTINGS = %w[ai_features_enabled ai_response_timeout alpha_vantage_api_key anthropic_access_token anthropic_base_url anthropic_model eodhd_api_key exchange_rate_provider external_ai_enabled external_assistant_agent_id external_assistant_model external_assistant_token external_assistant_url external_market_data_enabled jev_api_key jev_endpoint jev_model llm_context_window llm_max_items_per_call llm_max_response_tokens llm_provider mansa_api_key openai_access_token openai_json_mode openai_model openai_request_timeout openai_uri_base securities_provider securities_providers tiingo_api_key tinkoff_invest_api_key twelve_data_api_key].freeze
  PROVIDER_TYPES = %w[AkahuAccount BinanceAccount BrexAccount CoinbaseAccount CoinspotAccount CoinstatsAccount FinancekitAccount FioAccount IbkrAccount IndexaCapitalAccount KrakenAccount LunchflowAccount MercuryAccount MonobankAccount OnchainWalletAccount PlaidAccount QuestradeAccount RedbarkAccount SimplefinAccount SnaptradeAccount SophtronAccount TradeRepublicAccount Trading212Account UpAccount WiseAccount FinancekitAccountLineage].freeze
  ITEM_TYPES = %w[AkahuItem BinanceItem BrexItem CoinbaseItem CoinspotItem CoinstatsItem FinancekitItem FioItem IbkrItem IndexaCapitalItem KrakenItem LunchflowItem MercuryItem MonobankItem OnchainWalletItem PlaidItem QuestradeItem RedbarkItem SimplefinItem SnaptradeItem SophtronItem TradeRepublicItem Trading212Item UpItem WiseItem].freeze

  # A migration-local reader converts retained performance data before dropping
  # the connector table. It has no callbacks or network behaviour.
  class PerformanceRecord < ActiveRecord::Base
    self.table_name = "indexa_capital_accounts"
    encrypts :raw_payload, support_unencrypted_data: true if ActiveRecordEncryptionConfig.explicitly_configured?
  end

  def up
    add_column :holdings, :imported_snapshot, :boolean, default: false, null: false
    add_column :accounts, :reverse_balance_history, :boolean, default: false, null: false
    add_column :accounts, :imported_balance_history, :jsonb, default: [], null: false
    add_column :accounts, :imported_performance, :jsonb, default: {}, null: false
    add_column :accounts, :managed_portfolio, :boolean, default: false, null: false
    preserve_performance_history
    execute <<~SQL
      UPDATE accounts SET reverse_balance_history = TRUE
      WHERE plaid_account_id IS NOT NULL OR simplefin_account_id IS NOT NULL
        OR id IN (SELECT account_id FROM account_providers WHERE provider_type IN (#{quoted(PROVIDER_TYPES)}))
    SQL
    execute <<~SQL
      UPDATE accounts SET imported_balance_history = COALESCE((
        SELECT jsonb_agg(jsonb_build_object('report_date', balances.date, 'total', balances.balance::text, 'currency', balances.currency) ORDER BY balances.date)
        FROM balances WHERE balances.account_id = accounts.id AND UPPER(balances.currency) = UPPER(accounts.currency)
      ), '[]'::jsonb)
      WHERE id IN (SELECT account_id FROM account_providers WHERE provider_type = 'IbkrAccount')
    SQL
    execute "UPDATE holdings SET account_provider_id = NULL, imported_snapshot = TRUE WHERE account_provider_id IN (SELECT id FROM account_providers WHERE provider_type IN (#{quoted(PROVIDER_TYPES)}))"
    execute "DELETE FROM account_providers WHERE provider_type IN (#{quoted(PROVIDER_TYPES)})"
    execute "UPDATE accounts SET account_providers_count = (SELECT COUNT(*) FROM account_providers WHERE account_id = accounts.id)"
    # Sync is a shared domain; remove only rows for retired connector types.
    execute "UPDATE syncs SET parent_id = NULL WHERE parent_id IN (SELECT id FROM syncs WHERE syncable_type IN (#{quoted(ITEM_TYPES)}))"
    execute "DELETE FROM syncs WHERE syncable_type IN (#{quoted(ITEM_TYPES)})"
    execute "DELETE FROM import_source_mappings WHERE source_type IN ('RecurringTransaction', 'RecurringOccurrence') OR target_type IN (#{quoted(PROVIDER_TYPES + %w[RecurringTransaction RecurringOccurrence])})"
    execute "DELETE FROM insights WHERE insight_type IN ('cash_flow_warning', 'subscription_audit')"
    execute "DELETE FROM settings WHERE var IN (#{quoted(SETTINGS)})"
    # Attachments on discarded conversations/connectors are removed. Shared blobs
    # remain; use Active Storage's unattached-blob purge separately after backup.
    execute "DELETE FROM active_storage_attachments WHERE record_type IN (#{quoted(ITEM_TYPES + PROVIDER_TYPES + %w[Chat Message ToolCall])})"
    connection.tables.each do |table|
      connection.foreign_keys(table).each do |foreign_key|
        remove_foreign_key table, name: foreign_key.name if TABLES.include?(table) || TABLES.include?(foreign_key.to_table)
      end
    end
    COLUMNS.each do |table, fields|
      fields.each { |field| remove_column table, field }
    end
    TABLES.each { |table| drop_table table }
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Restore the pre-phase-10 database and local storage backup; recreating empty tables cannot recover discarded data."
  end

  private
    def preserve_performance_history
      PerformanceRecord.reset_column_information
      connection.select_rows("SELECT account_id, provider_id FROM account_providers WHERE provider_type = 'IndexaCapitalAccount'").each do |account_id, provider_id|
        payload = PerformanceRecord.find(provider_id).raw_payload.to_h
        history = payload.fetch("performance_history", {})
        execute "UPDATE accounts SET managed_portfolio = TRUE, imported_performance = #{connection.quote(history.to_json)}::jsonb WHERE id = #{connection.quote(account_id)}"
      end
    end

    def quoted(values)
      values.map { |value| connection.quote(value) }.join(", ")
    end
end
