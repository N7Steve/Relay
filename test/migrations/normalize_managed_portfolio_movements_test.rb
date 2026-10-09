require "test_helper"
require Rails.root.join("db/migrate/20261009120000_normalize_managed_portfolio_movements")

class NormalizeManagedPortfolioMovementsTest < ActiveSupport::TestCase
  test "normalizes all families without depending on names and preserves complete history" do
    families = [ families(:empty), families(:dylan_family) ]
    entries = families.map do |family|
      account = family.accounts.create!(name: SecureRandom.hex, currency: "USD", balance: 1000,
        accountable: Investment.new(subtype: "roboadvisor"))
      entry = account.entries.create!(name: "Arbitrary old title", date: Date.current, amount: -114.71,
        currency: "USD", notes: "Preserve", excluded: true,
        entryable: Transaction.new(extra: { "source" => { "original" => "keep" } }))
      category = family.categories.create!(name: SecureRandom.hex)
      entry.transaction.update_column(:category_id, category.id)
      entry.transaction.tags << family.tags.create!(name: SecureRandom.hex)
      [ entry, entry.attributes, entry.transaction.attributes ]
    end
    ordinary = entries(:transaction)
    ordinary_before = ordinary.transaction.attributes
    ActiveRecord::Migration.suppress_messages { NormalizeManagedPortfolioMovements.new.up }
    entries.each do |entry, before, transaction_before|
      assert_equal before, entry.reload.attributes
      transaction = entry.transaction.reload
      assert transaction.investment_value_adjustment?
      assert_equal transaction_before.except("kind", "extra"), transaction.attributes.except("kind", "extra")
      assert_equal "keep", transaction.extra.dig("source", "original")
    end
    assert_equal ordinary_before, ordinary.transaction.reload.attributes
    after = entries.map { |entry,| entry.transaction.reload.attributes }
    ActiveRecord::Migration.suppress_messages { NormalizeManagedPortfolioMovements.new.up }
    assert_equal after, entries.map { |entry,| entry.transaction.reload.attributes }
    ActiveRecord::Migration.suppress_messages { NormalizeManagedPortfolioMovements.new.down }
    entries.each do |entry, _, before|
      assert_equal before, entry.transaction.reload.attributes
    end
  end

  test "uses tracking mode and preserves paired transfers and positions accounts" do
    family = families(:dylan_family)
    managed = family.accounts.create!(name: "Renamed pension", currency: "USD", balance: 0,
      accountable: Investment.new(subtype: "pension", tracking_mode: "managed"))
    positions = family.accounts.create!(name: "Positions", currency: "USD", balance: 0,
      accountable: Investment.new(subtype: "roboadvisor", tracking_mode: "positions"))
    contribution = managed.entries.create!(name: "Deposit", currency: "USD", amount: -100, date: Date.current,
      entryable: Transaction.new(investment_activity_label: "Contribution"))
    ordinary = positions.entries.create!(name: "Ordinary", currency: "USD", amount: -20, date: Date.current,
      entryable: Transaction.new)
    transfer = transfers(:one)
    transfer.inflow_transaction.entry.update!(account: managed)
    transfer.inflow_transaction.update_column(:kind, "standard")
    original_transfer = transfer.inflow_transaction.attributes
    original_entry = transfer.inflow_transaction.entry.attributes

    ActiveRecord::Migration.suppress_messages { NormalizeManagedPortfolioMovements.new.up }
    assert_predicate contribution.transaction.reload, :investment_contribution?
    assert_predicate ordinary.transaction.reload, :standard?
    assert_equal original_transfer, transfer.inflow_transaction.reload.attributes
    assert_equal original_entry, transfer.inflow_transaction.entry.reload.attributes
    assert Transfer.exists?(transfer.id)
  end
end
