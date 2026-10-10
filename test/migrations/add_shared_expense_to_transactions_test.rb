require "test_helper"
require Rails.root.join("db/migrate/20261010120000_add_shared_expense_to_transactions")

class AddSharedExpenseToTransactionsTest < ActiveSupport::TestCase
  test "converts expenses and settlements in every family preserving all historical attributes and tags" do
    entries = [ families(:empty), families(:dylan_family) ].flat_map do |family|
      tag = family.tags.create!(name: "Gastos compartidos", color: "#123456")
      account = family.accounts.create!(name: "History", balance: 0, currency: "EUR", accountable: Depository.new)
      [ 101, -30 ].map do |amount|
        account.entries.create!(name: "History", amount: amount, currency: "EUR", date: Date.new(2020, 2, 3), notes: "Keep", excluded: true,
          entryable: Transaction.new(tags: [ tag ], extra: { "original" => true }))
      end
    end
    before = entries.map { |entry| [ entry.attributes, entry.transaction.attributes, entry.transaction.tag_ids ] }
    ordinary = transactions(:one)
    ordinary_before = ordinary.attributes
    migrate_up
    entries.zip(before).each do |entry, (entry_attrs, transaction_attrs, tags)|
      assert_equal entry_attrs, entry.reload.attributes
      assert_equal transaction_attrs.merge("shared_expense" => true), entry.transaction.reload.attributes
      assert_equal tags, entry.transaction.tag_ids
    end
    assert_equal ordinary_before, ordinary.reload.attributes
    after = entries.map { |entry| entry.transaction.reload.attributes }
    migrate_up
    assert_equal after, entries.map { |entry| entry.transaction.reload.attributes }
  end

  private
    def migrate_up
      ActiveRecord::Migration.suppress_messages { AddSharedExpenseToTransactions.new.up }
    end
end
