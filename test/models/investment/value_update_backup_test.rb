require "test_helper"

class Investment::ValueUpdateBackupTest < ActiveSupport::TestCase
  test "exports and restores absolute values and legacy categories without altering their deltas" do
    family = families(:empty)
    account = family.accounts.create!(name: "Managed backup", currency: "USD", balance: 1000,
      accountable: Investment.new(subtype: "roboadvisor"))
    account.entries.create!(date: Date.current - 3, amount: 1000, currency: "USD", name: "Opening",
      entryable: Valuation.new(kind: "opening_anchor"))
    update = Investment::ValueUpdate.new(account: account, date: Date.current - 1, amount: "1114.71")
    assert update.save
    category = family.categories.create!(name: "Old category")
    update.entry.transaction.update_column(:category_id, category.id)

    Zip::File.open_buffer(Family::DataExporter.new(family).generate_export) do |zip|
      # Exercise the portable legacy records too; full snapshots retain all extra metadata.
      lines = zip.read("all.ndjson").each_line.reject { |line| JSON.parse(line)["type"].start_with?("Backup") }.join
      destination = families(:dylan_family)
      Family::DataImporter.new(destination, lines).import!
      restored = destination.accounts.find_by!(name: "Managed backup")
      entry = restored.entries.transactions.find_by!(name: update.entry.name)
      assert_equal update.entry.amount, entry.amount
      assert_equal update.entry.transaction.extra["investment_value"], entry.transaction.extra["investment_value"]
      assert_equal "Old category", entry.transaction.category.name
      Account::Recalculator.new(restored).recalculate
      assert_equal BigDecimal("1114.71"), restored.reload.balance
    end
  end
end
