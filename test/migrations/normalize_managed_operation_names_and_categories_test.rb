require "test_helper"
require Rails.root.join("db/migrate/20261009133000_normalize_managed_operation_names_and_categories")

class NormalizeManagedOperationNamesAndCategoriesTest < ActiveSupport::TestCase
  test "normalizes history in all families and preserves originals and every monetary attribute" do
    snapshots = [ families(:empty), families(:dylan_family) ].flat_map do |family|
      family.update!(locale: "es")
      bank = family.accounts.create!(name: "Bank", balance: 1000, currency: "USD", accountable: Depository.new)
      portfolio = family.accounts.create!(name: "Renamed portfolio", balance: 0, currency: "USD", accountable: Investment.new(subtype: "roboadvisor"))
      category = family.categories.create!(name: SecureRandom.hex)
      transfer = Transfer::Creator.new(family: family, source_account_id: bank.id, destination_account_id: portfolio.id,
        date: Date.current, amount: 100).create
      adjustment = portfolio.entries.create!(name: "Old valuation", date: Date.current, amount: -114.71,
        currency: "USD", notes: "Keep", entryable: Transaction.new(kind: "investment_value_adjustment"))
      [ transfer.outflow_transaction.entry, transfer.inflow_transaction.entry, adjustment ].map do |entry|
        entry.update_columns(name: "Arbitrary old title")
        entry.transaction.update_columns(category_id: category.id, extra: { "provider" => { "keep" => true } })
        [ entry, entry.attributes, entry.transaction.attributes ]
      end
    end
    ordinary = entries(:transaction)
    ordinary_before = [ ordinary.attributes, ordinary.transaction.attributes ]
    migrate_up
    snapshots.each do |entry, entry_before, transaction_before|
      assert_equal entry_before.except("name"), entry.reload.attributes.except("name")
      assert_equal transaction_before.except("category_id", "extra"), entry.transaction.reload.attributes.except("category_id", "extra")
      assert_nil entry.transaction.category_id
      assert_equal "Arbitrary old title", entry.transaction.extra.dig("native_operation_original", "name")
      assert_equal transaction_before["category_id"], entry.transaction.extra.dig("native_operation_original", "category_id")
      assert entry.transaction.extra.dig("provider", "keep")
      assert_match entry.transaction.investment_value_adjustment? ? /\AValoración \d{2}\/\d{2}\/\d{4}\z/ : /\AAportación · Renamed portfolio\z/, entry.name
    end
    assert_equal ordinary_before, [ ordinary.reload.attributes, ordinary.transaction.reload.attributes ]
    after = snapshots.map { |entry,| [ entry.reload.attributes, entry.transaction.reload.attributes ] }
    migrate_up
    assert_equal after, snapshots.map { |entry,| [ entry.reload.attributes, entry.transaction.reload.attributes ] }
    ActiveRecord::Migration.suppress_messages { NormalizeManagedOperationNamesAndCategories.new.down }
    snapshots.each do |entry, entry_before, transaction_before|
      assert_equal entry_before, entry.reload.attributes
      assert_equal transaction_before, entry.transaction.reload.attributes
    end
  end

  test "normalizes withdrawals portfolio transfers and unpaired contributions in English" do
    family = families(:empty)
    family.update!(locale: "en")
    bank = family.accounts.create!(name: "Bank", balance: 1000, currency: "USD", accountable: Depository.new)
    first = family.accounts.create!(name: "First", balance: 1000, currency: "USD", accountable: Investment.new(subtype: "roboadvisor"))
    second = family.accounts.create!(name: "Second", balance: 0, currency: "USD", accountable: Investment.new(tracking_mode: "managed", subtype: "pension"))
    withdrawal = Transfer::Creator.new(family: family, source_account_id: first.id, destination_account_id: bank.id,
      date: Date.current, amount: 100).create
    between = Transfer::Creator.new(family: family, source_account_id: first.id, destination_account_id: second.id,
      date: Date.current, amount: 100).create
    standalone = first.entries.create!(name: "Legacy", date: Date.current, amount: -50, currency: "USD",
      entryable: Transaction.new(kind: "investment_contribution"))
    expectations = {
      withdrawal.outflow_transaction.entry => "Withdrawal · First",
      withdrawal.inflow_transaction.entry => "Withdrawal · First",
      between.outflow_transaction.entry => "Portfolio transfer · First → Second",
      between.inflow_transaction.entry => "Portfolio transfer · First → Second",
      standalone => "Contribution · First"
    }
    expectations.each_key { |entry| entry.update_columns(name: "Arbitrary legacy name") }
    migrate_up
    expectations.each do |entry, expected_name|
      assert_equal expected_name, entry.reload.name
      assert_nil entry.transaction.reload.category_id
      assert_equal "Arbitrary legacy name", entry.transaction.extra.dig("native_operation_original", "name")
    end
  end

  private
    def migrate_up
      ActiveRecord::Migration.suppress_messages { NormalizeManagedOperationNamesAndCategories.new.up }
    end
end
