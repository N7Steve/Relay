require "test_helper"

class Investment::ValueUpdateBackupTest < ActiveSupport::TestCase
  test "exports and restores absolute values and original category metadata without altering their deltas" do
    family = families(:empty)
    account = family.accounts.create!(name: "Managed backup", currency: "USD", balance: 1000,
      accountable: Investment.new(subtype: "roboadvisor"))
    account.entries.create!(date: Date.current - 3, amount: 1000, currency: "USD", name: "Opening",
      entryable: Valuation.new(kind: "opening_anchor"))
    update = Investment::ValueUpdate.new(account: account, date: Date.current - 1, amount: "1114.71")
    assert update.save
    category = family.categories.create!(name: "Old category")
    update.entry.transaction.update!(extra: update.entry.transaction.extra.merge("native_operation_original" => {
      "version" => 1, "name" => "Old title", "category_id" => category.id, "category_name" => category.name
    }))

    Zip::File.open_buffer(Family::DataExporter.new(family).generate_export) do |zip|
      # Exercise the portable legacy records too; full snapshots retain all extra metadata.
      lines = zip.read("all.ndjson").each_line.reject { |line| JSON.parse(line)["type"].start_with?("Backup") }.join
      destination = families(:dylan_family)
      Family::DataImporter.new(destination, lines).import!
      restored = destination.accounts.find_by!(name: "Managed backup")
      entry = restored.entries.transactions.find_by!(name: update.entry.name)
      assert_equal update.entry.amount, entry.amount
      assert_equal update.entry.transaction.extra["investment_value"], entry.transaction.extra["investment_value"]
      assert_nil entry.transaction.category
      assert_equal "Old category", entry.transaction.extra.dig("native_operation_original", "category_name")
      assert_equal "Old title", entry.transaction.extra.dig("native_operation_original", "name")
      Account::Recalculator.new(restored).recalculate
      assert_equal BigDecimal("1114.71"), restored.reload.balance
    end
  end
end
