require "test_helper"

class Mcp::ChangeSet::SummaryTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @account = accounts(:depository)
    @destination = accounts(:connected)
  end

  test "separates expenses income and transfers by account and currency without netting them" do
    set = proposal([
      operation("create_transaction", account_id: @account.id, amount: "12", currency: "EUR"),
      operation("create_transaction", account_id: @account.id, amount: "3", currency: "EUR"),
      operation("create_transaction", account_id: @account.id, amount: "2", currency: "USD"),
      operation("create_transaction", account_id: @account.id, amount: "-8", currency: "EUR"),
      operation("create_transaction", account_id: @destination.id, amount: "1", currency: "EUR"),
      operation("create_transfer", source_account_id: @account.id, destination_account_id: @destination.id, amount: "5")
    ])
    groups = summary(set)
    assert_equal 5, groups.size
    expenses = groups.find { |group| group[:type] == "expenses" && group[:count] == 2 }
    assert_equal BigDecimal("15"), expenses[:amount]
    assert_equal "EUR", expenses[:currency]
    assert_equal({ "pending" => 2 }, expenses[:states])
    assert_equal BigDecimal("8"), groups.find { |group| group[:type] == "income" }[:amount]
    transfer = groups.find { |group| group[:type] == "transfers" }
    assert_equal [ @account.name, @destination.name ], transfer[:accounts].pluck(:name)
    assert_equal BigDecimal("5"), transfer[:amount]
    assert_equal @account.currency, transfer[:currency]
  end

  test "groups organization changes by type and retains their names" do
    set = proposal([
      operation("create_category", name: "Groceries"), operation("create_category", name: "Travel"),
      operation("create_tag", name: "Test"), operation("create_merchant", name: "Shop"),
      operation("create_rule", name: "Automatic label")
    ])
    groups = summary(set)
    assert_equal %w[categories tags merchants rules], groups.pluck(:type)
    assert_equal [ "Groceries", "Travel" ], groups.first[:names]
    assert_equal 2, groups.first[:count]
    assert_nil groups.first[:amount]
  end

  test "edits and deletes identify existing transactions without promising a balance delta" do
    entry = @account.entries.create!(name: "Expense", date: Date.current, amount: 7, currency: "USD", entryable: Transaction.new)
    set = proposal([
      operation("delete_transaction", transaction_id: entry.entryable_id),
      operation("update_transaction", transaction_id: entry.entryable_id, amount: "-10")
    ])
    groups = summary(set)
    assert_equal %w[expenses income], groups.pluck(:type)
    assert_equal %w[delete update], groups.pluck(:action)
    assert_equal @account.name, groups.first[:accounts].first[:name]
    assert groups.all? { |group| group[:amount].nil? }
  end

  test "revoked and foreign accounts never disclose current labels or transaction details" do
    entry = @account.entries.create!(name: "Private expense", date: Date.current, amount: 7, currency: "USD", entryable: Transaction.new)
    @account.update!(owner: users(:family_member))
    @account.account_shares.where(user: @user).delete_all
    foreign_account = users(:empty).family.accounts.create!(name: "Foreign private account", currency: "EUR", balance: 0, accountable: Depository.new)
    set = proposal([
      operation("create_transfer", source_account_id: @account.id, destination_account_id: foreign_account.id, amount: "5"),
      operation("delete_transaction", transaction_id: entry.entryable_id)
    ])
    groups = summary(set)
    assert_equal [ nil, nil ], groups.first[:accounts].pluck(:name)
    assert_nil groups.first[:amount]
    assert_equal "transactions", groups.last[:type]
    assert_empty groups.last[:accounts]
  end

  test "pending account references use proposed labels and never guess dependent amounts" do
    account = operation("create_account", name: "New account", currency: "EUR")
    set = proposal([
      account,
      operation("create_transaction", account_id: "pending:#{account['id']}:id", amount: "pending:#{account['id']}:balance", currency: "EUR")
    ])
    group = summary(set).last
    assert_equal "transactions", group[:type]
    assert_equal({ name: "New account", proposed: true }, group[:accounts].first)
    assert_nil group[:amount]
  end

  test "partially applied and discarded proposals retain per group execution counts" do
    applied = operation("create_tag", name: "Applied").merge("status" => "applied")
    failed = operation("create_tag", name: "Failed").merge("status" => "failed")
    pending = operation("create_tag", name: "Not reached")
    set = proposal([ applied, failed, pending ])
    assert_equal({ "applied" => 1, "failed" => 1, "pending" => 1 }, summary(set).first[:states])
    set.status = "rejected"
    assert_equal({ "applied" => 1, "rejected" => 2 }, summary(set).first[:states])
  end

  private
    def operation(name, **arguments)
      { "id" => SecureRandom.uuid, "name" => name, "arguments" => arguments.stringify_keys, "status" => "pending" }
    end

    def proposal(operations)
      Mcp::ChangeSet.new(id: SecureRandom.uuid, user: @user, family: @user.family, credential_name: "Test", operations: operations)
    end

    def summary(set)
      Mcp::ChangeSet::Summary.new(change_sets: [ set ], actor: @user).groups(set)
    end
end
