require "test_helper"

class Family::Backup::DiscardPolicyTest < ActiveSupport::TestCase
  setup do
    @source = Family.create!(name: "Previous product", currency: "EUR")
    @account = @source.accounts.create!(name: "Imported investment", balance: 123, currency: "EUR", accountable: Investment.new)
    @target = Family.create!(name: "Recovery", currency: "EUR")
    @target.users.create!(email: "phase10-recovery@example.com", password: "password123", role: "admin")
  end

  test "recovers core records and originals from an old snapshot with every retired module" do
    @account.custom_logo.attach(io: StringIO.new(file_fixture("square-placeholder.png").binread), filename: "account.png", content_type: "image/png")
    @account.holdings.create!(security: securities(:aapl), date: Date.current, qty: 1, price: 123, amount: 123, currency: "EUR")
    @account.balances.create!(date: Date.current, balance: 123, cash_balance: 0, currency: "EUR")
    provider_id = SecureRandom.uuid
    content = historical_snapshot do |rows|
      Family::Backup::DiscardPolicy::MODELS.each do |name|
        rows << record(name, "id" => SecureRandom.uuid, "family_id" => @source.id)
      end
      rows << record("AccountProvider", "id" => provider_id, "account_id" => @account.id,
        "provider_type" => "IbkrAccount", "provider_id" => SecureRandom.uuid)
      rows.find { |row| row.dig("data", "model") == "Holding" }["data"]["attributes"]["account_provider_id"] = provider_id
      account_attrs = rows.find { |row| row.dig("data", "model") == "Account" }["data"]["attributes"]
      account_attrs["plaid_account_id"] = SecureRandom.uuid
      account_attrs["account_providers_count"] = 1
      family_attrs = rows.find { |row| row.dig("data", "model") == "Family" }["data"]["attributes"]
      family_attrs["assistant_type"] = "external"
    end

    preflight = SureImport::Preflight.new(family: @target, content: content).call
    assert preflight.valid?, preflight.error_message
    assert_equal "retired_data_discarded", preflight.warnings.sole[:code]
    result = Family::DataImporter.new(@target, content).import!
    assert_equal "supported_product", result[:verification]["scope"]
    restored = @target.accounts.sole
    assert restored.manual?
    assert_equal 0, restored.account_providers_count
    assert restored.reverse_balance_history?
    assert restored.holdings.sole.imported_snapshot?
    assert_nil restored.holdings.sole.account_provider_id
    assert_equal "123.0", restored.imported_balance_history.sole["total"].to_d.to_s("F")
    assert_equal file_fixture("square-placeholder.png").binread, restored.custom_logo.download
    assert_equal @account.balance, restored.balance
    assert_empty restored.account_providers
    omissions = result[:verification]["warnings"].sole[:details][:records]
    Family::Backup::DiscardPolicy::MODELS.each { |name| assert_equal 1, omissions[name] }

    second_target = Family.create!(name: "Second recovery", currency: "EUR")
    second_target.users.create!(email: "second-phase10-recovery@example.com", password: "password123", role: "admin")
    second_result = Family::DataImporter.new(second_target, Family::Backup.new(@target).generate_ndjson).import!
    assert_empty second_result[:verification]["warnings"]
    assert second_target.accounts.sole.holdings.sole.imported_snapshot?
    assert_equal restored.imported_balance_history, second_target.accounts.sole.imported_balance_history
  end

  test "discarded attachments are reported after verifying their bytes" do
    chat_id = SecureRandom.uuid
    content = historical_snapshot do |rows|
      rows << record("Chat", "id" => chat_id)
      rows << { "type" => "BackupAttachment", "data" => {
        "model" => "Chat", "record_id" => chat_id, "content" => Base64.strict_encode64("old bytes"),
        "byte_size" => 9, "checksum" => Digest::MD5.base64digest("old bytes")
      } }
    end
    result = Family::DataImporter.new(@target, content).import!
    assert_equal 1, result[:verification]["warnings"].sole[:details][:records]["Chat attachments"]
    assert_equal 0, result[:verification]["verified_attachments"]
  end

  test "preserves managed portfolio performance without retaining its connector" do
    performance = { "return" => { "index" => { "2026-09-30" => "100", "2026-10-01" => "105" } } }
    content = historical_snapshot do |rows|
      provider_id = SecureRandom.uuid
      rows << record("IndexaCapitalAccount", "id" => provider_id, "raw_payload" => { "performance_history" => performance })
      rows << record("AccountProvider", "id" => SecureRandom.uuid, "account_id" => @account.id,
        "provider_type" => "IndexaCapitalAccount", "provider_id" => provider_id)
    end
    Family::DataImporter.new(@target, content).import!
    restored = @target.accounts.sole
    assert restored.managed_portfolio?
    assert_equal performance, restored.imported_performance
    assert_equal 0.05.to_d, Investment::RoboadvisorPerformance.new(restored).rate_for(Date.new(2026, 10, 1)..Date.new(2026, 10, 1))
    assert_empty restored.account_providers
  end

  test "missing managed portfolio payload fails instead of silently losing performance" do
    content = historical_snapshot do |rows|
      rows << record("AccountProvider", "id" => SecureRandom.uuid, "account_id" => @account.id,
        "provider_type" => "IndexaCapitalAccount", "provider_id" => SecureRandom.uuid)
    end
    assert_no_difference "Account.count" do
      assert_raises(Family::Backup::InvalidBackupError) { Family::DataImporter.new(@target, content).import! }
    end
  end

  test "unknown modules and missing core references still fail atomically" do
    [ "FutureModule", "AccountShare" ].each do |name|
      content = historical_snapshot do |rows|
        rows << record(name, "id" => SecureRandom.uuid, "account_id" => SecureRandom.uuid)
      end
      assert_no_difference "Account.count" do
        assert_raises(Family::Backup::InvalidBackupError) { Family::DataImporter.new(@target, content).import! }
      end
    end
  end

  test "a bad checksum in discarded data cannot bypass integrity validation" do
    content = historical_snapshot { |rows| rows << record("Chat", "id" => SecureRandom.uuid) }
    assert_raises(Family::Backup::InvalidBackupError) do
      Family::DataImporter.new(@target, content.sub('"model":"Chat"', '"model":"Message"')).import!
    end
  end

  test "legacy Bills imports warn and report discards while retaining transactions" do
    content = [
      { type: "Account", data: { id: "old-account", name: "Checking", balance: "100", currency: "EUR", accountable_type: "Depository" } },
      { type: "Transaction", data: { id: "old-payment", account_id: "old-account", name: "Payment", amount: "10", currency: "EUR", date: "2026-10-01" } },
      { type: "RecurringTransaction", data: { id: "old-series" } }
    ].map(&:to_json).join("\n")
    preflight = SureImport::Preflight.new(family: @target, content: content).call
    assert preflight.valid?, preflight.error_message
    assert preflight.warnings.any? { |warning| warning[:code] == "retired_data_discarded" }
    result = Family::DataImporter.new(@target, content).import!
    assert_equal 1, @target.transactions.count
    assert_equal 1, result[:summary]["discarded_retired_modules"]["RecurringTransaction"]
  end

  private
    def record(name, attrs)
      { "type" => "BackupRecord", "data" => { "model" => name, "attributes" => attrs } }
    end

    def historical_snapshot
      rows = Family::Backup.new(@source).generate_ndjson.lines.map { |line| JSON.parse(line) }
      yield rows
      payload = rows.drop(1).map(&:to_json).join("\n")
      rows.first["data"]["sha256"] = Digest::SHA256.hexdigest(payload)
      rows.map(&:to_json).join("\n")
    end
end
