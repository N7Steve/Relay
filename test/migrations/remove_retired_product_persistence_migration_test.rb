require "test_helper"
require Rails.root.join("db/migrate/20261005120000_remove_retired_product_persistence")

class RemoveRetiredProductPersistenceMigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  test "upgrades the phase 9 schema while preserving financial history and retained settings" do
    connection = ActiveRecord::Base.connection
    original_path = connection.schema_search_path
    expected_columns = connection.tables.excluding("schema_migrations", "ar_internal_metadata").to_h do |table|
      [ table, connection.columns(table).map { |column| [ column.name, column.sql_type, column.default, column.null ] }.sort_by(&:first) ]
    end
    schema = "phase10_#{SecureRandom.hex(8)}"
    connection.execute("CREATE SCHEMA #{schema}")
    connection.schema_search_path = schema
    ActiveRecord::Migration.suppress_messages { load file_fixture("pruning_phase9_schema.rb.txt") }
    family_id = insert_row(connection, "families", name: "Upgrade family", currency: "EUR", stripe_customer_id: "retired-customer")
    account_id = insert_row(connection, "accounts", family_id: family_id, name: "Investment", accountable_type: "Investment", currency: "eur", balance: 123)
    provider_id = insert_row(connection, "account_providers", account_id: account_id, provider_type: "IbkrAccount", provider_id: SecureRandom.uuid)
    security_id = insert_row(connection, "securities", ticker: "LOCAL", price_provider: "retired")
    holding_id = insert_row(connection, "holdings", account_id: account_id, account_provider_id: provider_id, security_id: security_id, date: "2026-10-01", qty: 1, price: 123, amount: 123, currency: "EUR")
    balance_id = insert_row(connection, "balances", account_id: account_id, date: "2026-10-01", balance: 123, cash_balance: 0, currency: "EUR")
    insert_row(connection, "settings", var: "external_assistant_token", value: "retired-secret")
    insert_row(connection, "settings", var: "brand_fetch_client_id", value: "keep-logo-setting")
    insert_row(connection, "settings", var: "external_google_drive_enabled", value: "true")
    before = connection.select_one("SELECT * FROM balances WHERE id = '#{balance_id}'")
    managed_id = insert_row(connection, "accounts", family_id: family_id, name: "Managed pension", accountable_type: "Investment", currency: "EUR", balance: 456)
    item_id = insert_row(connection, "indexa_capital_items", family_id: family_id)
    performance = { "2026-10-01" => { "value" => 456, "return" => 0.05 } }
    RemoveRetiredProductPersistence::PerformanceRecord.reset_column_information
    managed_provider_id = RemoveRetiredProductPersistence::PerformanceRecord.create!(
      indexa_capital_item_id: item_id, raw_payload: { "performance_history" => performance }
    ).id
    insert_row(connection, "account_providers", account_id: managed_id, provider_type: "IndexaCapitalAccount", provider_id: managed_provider_id)
    plain_managed_id = insert_row(connection, "accounts", family_id: family_id, name: "Plain managed portfolio", accountable_type: "Investment", currency: "EUR", balance: 456)
    plain_provider_id = insert_row(connection, "indexa_capital_accounts", indexa_capital_item_id: item_id, raw_payload: { "performance_history" => performance }.to_json)
    insert_row(connection, "account_providers", account_id: plain_managed_id, provider_type: "IndexaCapitalAccount", provider_id: plain_provider_id)

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ActiveRecord::Migration.suppress_messages { RemoveRetiredProductPersistence.new.migrate(:up) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    assert_equal before, connection.select_one("SELECT * FROM balances WHERE id = '#{balance_id}'")
    assert_equal true, connection.select_value("SELECT reverse_balance_history FROM accounts WHERE id = '#{account_id}'")
    assert_equal true, connection.select_value("SELECT imported_snapshot FROM holdings WHERE id = '#{holding_id}'")
    assert_nil connection.select_value("SELECT account_provider_id FROM holdings WHERE id = '#{holding_id}'")
    assert_equal 0, connection.select_value("SELECT COUNT(*) FROM account_providers")
    assert_equal 0, connection.select_value("SELECT account_providers_count FROM accounts WHERE id = '#{account_id}'")
    history = JSON.parse(connection.select_value("SELECT imported_balance_history FROM accounts WHERE id = '#{account_id}'"))
    assert_equal 123.to_d, history.sole["total"].to_d
    assert_equal true, connection.select_value("SELECT managed_portfolio FROM accounts WHERE id = '#{managed_id}'")
    assert_equal performance, JSON.parse(connection.select_value("SELECT imported_performance FROM accounts WHERE id = '#{managed_id}'"))
    assert_equal performance, JSON.parse(connection.select_value("SELECT imported_performance FROM accounts WHERE id = '#{plain_managed_id}'"))
    assert_equal %w[brand_fetch_client_id external_google_drive_enabled], connection.select_values("SELECT var FROM settings ORDER BY var")
    RemoveRetiredProductPersistence::TABLES.each { |table| assert_not connection.table_exists?(table), table }
    %w[enable_banking_items exchange_rates security_prices scheduled_payments family_documents provider_request_counts oauth_access_tokens].each do |table|
      assert connection.table_exists?(table), table
    end
    RemoveRetiredProductPersistence::COLUMNS.each do |table, fields|
      assert_empty fields & connection.columns(table).map(&:name)
    end
    actual_columns = connection.tables.excluding("schema_migrations", "ar_internal_metadata").to_h do |table|
      [ table, connection.columns(table).map { |column| [ column.name, column.sql_type, column.default, column.null ] }.sort_by(&:first) ]
    end
    assert_equal expected_columns, actual_columns, "Fresh installation and upgraded schemas must agree"
    assert_raises(ActiveRecord::IrreversibleMigration) { RemoveRetiredProductPersistence.new.migrate(:down) }
    puts "Phase 10 isolated schema upgrade: #{elapsed.round(3)} seconds"
  ensure
    if connection && original_path
      connection.schema_search_path = original_path
      connection.execute("DROP SCHEMA IF EXISTS #{schema} CASCADE") if schema
      connection.schema_cache.clear!
    end
  end

  private
    def insert_row(connection, table, attrs)
      attrs = { id: SecureRandom.uuid, created_at: Time.current, updated_at: Time.current }.merge(attrs)
      attrs.delete(:id) if table == "settings"
      fields = attrs.keys.map { |field| connection.quote_column_name(field) }.join(", ")
      values = attrs.values.map { |value| connection.quote(value) }.join(", ")
      connection.select_value("INSERT INTO #{connection.quote_table_name(table)} (#{fields}) VALUES (#{values}) RETURNING id")
    end
end
