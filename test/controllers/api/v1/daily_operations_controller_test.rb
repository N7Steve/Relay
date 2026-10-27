# frozen_string_literal: true

require "test_helper"

class Api::V1::DailyOperationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @key = ApiKey.create!(user: @user, name: "Daily writes", scopes: %w[read_write], source: "web", display_key: "daily_#{SecureRandom.hex(12)}")
    @read_key = ApiKey.create!(user: @user, name: "Daily reads", scopes: %w[read], source: "web", display_key: "daily_read_#{SecureRandom.hex(12)}")
    @account = accounts(:depository)
  end

  test "all explicit operations require authentication" do
    Mcp::Catalog.all.each_key do |operation|
      post "/api/v1/actions/#{operation}", params: { arguments: {} }, as: :json
      assert_response :unauthorized, operation
    end
  end

  test "all writes reject a read key before any mutation" do
    # Use a complete set of schema-valid arguments for each operation to exercise
    # scope authorization rather than just the missing-parameter validator.
    Mcp::Catalog.all.each_value do |tool|
      next if tool[:annotations][:readOnlyHint]
      args = sample_arguments(tool[:inputSchema])
      post "/api/v1/actions/#{tool[:name]}", params: { arguments: args }, headers: headers(@read_key), as: :json
      assert_response :forbidden, "#{tool[:name]}: #{response.body}"
    end
  end

  test "account creation is idempotent for every maintained account type" do
    Accountable::TYPES.each do |type|
      args = { name: "API #{type}", balance: "125.50", currency: "USD", accountable_type: type, idempotency_key: "account-#{type}" }
      assert_difference "Account.count", 1 do
        invoke("create_account", args)
        assert_response :success, response.body
        @created_id = response.parsed_body.fetch("id")
        invoke("create_account", args)
        assert_response :success, response.body
        assert_equal @created_id, response.parsed_body.fetch("id")
      end
      assert_equal @user.id, Account.find(@created_id).owner_id
    end
  end

  test "account editing activation archive and default use native rules" do
    invoke("update_account", account_id: @account.id, name: "Updated", balance: "5500.25", idempotency_key: "edit-account")
    assert_response :success, response.body
    assert_equal "Updated", @account.reload.name
    invoke("set_account_status", account_id: @account.id, active: false, archived: true, idempotency_key: "disable")
    assert_response :success, response.body
    assert @account.reload.disabled?
    invoke("set_account_status", account_id: @account.id, active: true, archived: false, idempotency_key: "enable")
    assert_response :success, response.body
    invoke("set_default_account", account_id: @account.id, idempotency_key: "default")
    assert_response :success, response.body
    assert_equal @account.id, @user.reload.default_account_id
  end

  test "ledger signs replays collisions splits unsplit protection and deletion" do
    args = { account_id: @account.id, name: "Daily expense", date: Date.current.iso8601, amount: "12.50", idempotency_key: "txn-create" }
    assert_difference "Transaction.count", 1 do
      invoke("create_transaction", args)
      assert_response :success, response.body
      @transaction_id = response.parsed_body.fetch("transaction_id")
      invoke("create_transaction", args)
      assert_response :success
    end
    invoke("create_transaction", args.merge(amount: "20.00"))
    assert_response :unprocessable_entity
    invoke("split_transaction", transaction_id: @transaction_id, splits: [ { name: "A", amount: "5.00" }, { name: "B", amount: "7.50" } ], idempotency_key: "split")
    assert_response :success, response.body
    assert_equal 2, response.parsed_body.fetch("children").length, response.body
    child_id = response.parsed_body.fetch("children").first.fetch("transaction_id")
    invoke("delete_transaction", transaction_id: child_id, idempotency_key: "delete-child")
    assert_response :unprocessable_entity
    invoke("unsplit_transaction", transaction_id: @transaction_id, idempotency_key: "unsplit")
    assert_response :success, response.body
    invoke("protect_transaction", transaction_id: @transaction_id, protected: true, idempotency_key: "protect")
    assert_response :success
    invoke("unlock_transaction", transaction_id: @transaction_id, idempotency_key: "unlock")
    assert_response :success
    refute Transaction.find(@transaction_id).entry.protected_from_sync?
    invoke("update_transaction", transaction_id: @transaction_id, notes: "Annotated", idempotency_key: "annotate")
    assert_response :success
    invoke("bulk_update_transactions", transaction_ids: [ @transaction_id ], attributes: { name: "Bulk" }, idempotency_key: "bulk")
    assert_response :success, response.body
    assert_equal "Bulk", Transaction.find(@transaction_id).entry.name
    invoke("delete_transaction", transaction_id: @transaction_id, idempotency_key: "delete")
    assert_response :success
    refute Transaction.exists?(@transaction_id)
  end

  test "invalid dates decimals missing fields and unknown fields return 422" do
    base = { account_id: @account.id, name: "Bad", date: Date.current.iso8601, amount: "10.00", idempotency_key: "invalid" }
    [ base.merge(date: "2026-02-30"), base.merge(amount: "NaN"), base.except(:amount), base.merge(user_id: @user.id) ].each do |args|
      assert_no_difference "Entry.count" do
        invoke("create_transaction", args)
        assert_response :unprocessable_entity, response.body
      end
    end
  end

  test "cross family records references and second account permissions are rejected" do
    member = users(:family_member)
    member.update!(family: families(:empty))
    foreign = accounts(:other_asset)
    foreign.update!(family: families(:empty), owner: member)
    invoke("get_account", account_id: foreign.id)
    assert_response :not_found
    invoke("create_transfer", source_account_id: @account.id, destination_account_id: foreign.id, date: Date.current.iso8601, amount: "10.00", idempotency_key: "foreign-transfer")
    assert_response :not_found
    foreign_category = families(:empty).categories.create!(name: "Private", color: Category::COLORS.first, lucide_icon: "shapes")
    invoke("create_transaction", account_id: @account.id, name: "Bad ref", amount: "10", date: Date.current.iso8601, category_id: foreign_category.id, idempotency_key: "foreign-ref")
    assert_response :unprocessable_entity
  end

  test "annotation sharing never grants financial writes including replay" do
    member = users(:family_member)
    account = @account
    AccountShare.where(account: account, user: member).destroy_all
    AccountShare.create!(account: account, user: member, permission: "read_write")
    @key = ApiKey.create!(user: member, name: "Shared annotator", scopes: %w[read_write], source: "web", display_key: "shared_#{SecureRandom.hex(12)}")
    transaction = entries(:transaction).entryable
    invoke("update_transaction", transaction_id: transaction.id, notes: "Allowed", idempotency_key: "shared-note")
    assert_response :success, response.body
    invoke("update_transaction", transaction_id: transaction.id, amount: "99", idempotency_key: "shared-money")
    assert_response :forbidden
    invoke("create_transfer", source_account_id: account.id, destination_account_id: accounts(:credit_card).id, date: Date.current.iso8601, amount: "10", idempotency_key: "shared-transfer")
    assert_response :forbidden
  end

  test "transfer creation replay same and different currencies unlink and deletion" do
    %w[USD EUR].each do |currency|
      target = accounts(:credit_card)
      target.update!(currency: currency)
      args = { source_account_id: @account.id, destination_account_id: target.id, date: Date.current.iso8601,
        amount: "20.00", exchange_rate: "0.9", idempotency_key: "transfer-#{currency}" }
      invoke("create_transfer", args)
      assert_response :success, response.body
      transfer_id = response.parsed_body.fetch("id")
      invoke("create_transfer", args)
      assert_response :success, response.body
      assert_equal transfer_id, response.parsed_body.fetch("id")
      assert_equal "cc_payment", Transfer.find(transfer_id).outflow_transaction.kind
      action = currency == "USD" ? "unlink_transfer" : "delete_transfer"
      invoke(action, transfer_id: transfer_id, idempotency_key: "remove-#{currency}")
      assert_response :success, response.body
      refute Transfer.exists?(transfer_id)
    end
  end

  test "organization creates edits and merges categories merchants and tags" do
    %w[category merchant tag].each do |kind|
      ids = %w[Source Target].map do |name|
        invoke("create_#{kind}", name: "#{kind} #{name}", idempotency_key: "#{kind}-#{name}")
        assert_response :success, response.body
        response.parsed_body.fetch("id")
      end
      invoke("update_#{kind}", "#{kind}_id" => ids.last, "name" => "Edited #{kind}", "idempotency_key" => "edit-#{kind}")
      assert_response :success, response.body
      invoke("merge_#{kind.pluralize}", target_id: ids.last, source_ids: [ ids.first ], idempotency_key: "merge-#{kind}")
      assert_response :success, response.body
      invoke("list_#{kind.pluralize}", per_page: 1)
      assert_response :success
      assert_operator response.parsed_body.fetch("data").length, :<=, 1
      invoke("delete_#{kind}", "#{kind}_id" => ids.last, "idempotency_key" => "delete-#{kind}")
      assert_response :success, response.body
    end
  end

  test "read queries are paginated and operation status is actor scoped" do
    invoke("list_accounts", per_page: 1)
    assert_response :success
    assert_equal 1, response.parsed_body.fetch("data").length
    invoke("search_transactions", account_ids: [ @account.id ], per_page: 2, start_date: 1.year.ago.to_date.iso8601)
    assert_response :success, response.body
    assert_operator response.parsed_body.fetch("data").length, :<=, 2
    invoke("get_cash_flow", month: Date.current.beginning_of_month.iso8601)
    assert_response :success, response.body
    invoke("get_context", {})
    assert_response :success
    invoke("get_operation", idempotency_key: "nonexistent")
    assert_response :not_found
  end

  test "transfer matching editing rejecting and boundary nature use native models" do
    target = accounts(:credit_card)
    outflow = @account.entries.create!(name: "Out", amount: "15.00", currency: "USD", date: Date.current, entryable: Transaction.new)
    inflow = target.entries.create!(name: "In", amount: "-15.00", currency: "USD", date: Date.current, entryable: Transaction.new)
    invoke("match_transfer", outflow_transaction_id: outflow.entryable_id, inflow_transaction_id: inflow.entryable_id, idempotency_key: "match")
    assert_response :success, response.body
    transfer_id = response.parsed_body.fetch("id")
    assert_equal "cc_payment", outflow.reload.transaction.kind
    invoke("update_transfer", transfer_id: transfer_id, name: "Renamed", amount: "18.25", source_fee_amount: "1.50", idempotency_key: "edit-transfer")
    assert_response :success, response.body
    assert_equal BigDecimal("18.25"), outflow.reload.amount
    assert_equal BigDecimal("-18.25"), inflow.reload.amount
    assert_equal BigDecimal("1.50"), Transfer.find(transfer_id).derived_source_fee_amount
    invoke("update_transfer", transfer_id: transfer_id, status: "rejected", idempotency_key: "reject-transfer")
    assert_response :success, response.body
    assert RejectedTransfer.exists?(outflow_transaction_id: outflow.entryable_id, inflow_transaction_id: inflow.entryable_id)
    assert Entry.exists?(outflow.id)
    target.update!(financial_treatment: "outside_finances")
    invoke("create_transfer", source_account_id: @account.id, destination_account_id: target.id, amount: "3", date: Date.current.iso8601, idempotency_key: "boundary-transfer")
    assert_response :success, response.body
    assert_equal "transfer_to_excluded", response.parsed_body.dig("outflow", "transaction", "kind")
  end

  test "duplicate creation and conversion to a local trade preserve signs" do
    invoke("duplicate_transaction", transaction_id: entries(:transaction).entryable_id, date: Date.current.iso8601, idempotency_key: "duplicate")
    assert_response :success, response.body
    assert_equal entries(:transaction).amount, response.parsed_body.fetch("amount").to_d
    investment = accounts(:investment)
    entry = investment.entries.create!(name: "Buy", amount: "20", currency: "USD", date: Date.current, entryable: Transaction.new)
    invoke("convert_transaction_to_trade", transaction_id: entry.entryable_id, security_id: securities(:aapl).id, quantity: "2", price: "10", idempotency_key: "convert")
    assert_response :success, response.body
    trade = Trade.find(response.parsed_body.fetch("trade_id"))
    assert_equal BigDecimal("2"), trade.qty
    assert entry.reload.excluded?
  end

  test "duplicate decisions use the suggested same account pair" do
    posted = @account.entries.create!(name: "Posted", amount: "8", currency: "USD", date: Date.current, entryable: Transaction.new)
    pending = @account.entries.create!(name: "Pending", amount: "8", currency: "USD", date: Date.current, entryable: Transaction.new(extra: {
      "enable_banking" => { "pending" => true },
      "potential_posted_match" => { "entry_id" => posted.id, "reason" => "amount" }
    }))
    invoke("dismiss_duplicate", transaction_id: pending.entryable_id, idempotency_key: "dismiss")
    assert_response :success, response.body
    pending.transaction.update_columns(extra: pending.transaction.extra.merge("potential_posted_match" => { "entry_id" => posted.id }), posting_status: "pending")
    invoke("merge_duplicate", transaction_id: pending.entryable_id, idempotency_key: "merge-duplicate")
    assert_response :success, response.body
    refute Entry.exists?(pending.id)
    assert Entry.exists?(posted.id)
  end

  test "replacements transfer references and recalculation status is distinct from operation completion" do
    %w[category tag].each do |kind|
      invoke("create_#{kind}", name: "Replace source #{kind}", idempotency_key: "replace-source-#{kind}")
      source_id = response.parsed_body.fetch("id")
      invoke("create_#{kind}", name: "Replace target #{kind}", idempotency_key: "replace-target-#{kind}")
      target_id = response.parsed_body.fetch("id")
      invoke("replace_#{kind}", "#{kind}_id" => source_id, "replacement_id" => target_id, "idempotency_key" => "replace-#{kind}")
      assert_response :success, response.body
      assert_equal target_id, response.parsed_body.fetch("id")
    end
    invoke("get_operation", idempotency_key: "replace-tag")
    assert_response :success
    assert_equal "completed", response.parsed_body.fetch("status")
    refute response.parsed_body.key?("result")
    invoke("get_account_sync", account_id: @account.id)
    assert_response :success, response.body
    assert_equal @account.id, response.parsed_body.fetch("account_id")
  end

  test "bad split replacement rolls back children and parent atomically" do
    entry = entries(:transaction)
    invoke("split_transaction", transaction_id: entry.entryable_id, splits: [ { name: "A", amount: "4" }, { name: "B", amount: "6" } ], idempotency_key: "first-split")
    assert_response :success, response.body
    children = entry.child_entries.pluck(:id).sort
    invoke("split_transaction", transaction_id: entry.entryable_id, splits: [ { name: "A", amount: "1" }, { name: "B", amount: "2" } ], idempotency_key: "bad-replace")
    assert_response :unprocessable_entity
    assert_equal children, entry.child_entries.pluck(:id).sort
    assert entry.reload.excluded?
  end

  test "bulk delete binds preview to actor payload and current record versions" do
    entry = @account.entries.create!(name: "Bulk delete", date: Date.current, amount: "9", currency: "USD", entryable: Transaction.new)
    ids = [ entry.entryable_id ]
    invoke("preview_bulk_delete_transactions", transaction_ids: ids)
    assert_response :success, response.body
    token = response.parsed_body.fetch("preview_token")
    entry.update!(notes: "Changed after preview")
    invoke("bulk_delete_transactions", transaction_ids: ids, preview_token: token, idempotency_key: "stale-delete")
    assert_response :unprocessable_entity
    assert Entry.exists?(entry.id)
    invoke("preview_bulk_delete_transactions", transaction_ids: ids)
    assert_response :success
    token = response.parsed_body.fetch("preview_token")
    invoke("bulk_delete_transactions", transaction_ids: ids, preview_token: "tampered", idempotency_key: "tampered-delete")
    assert_response :unprocessable_entity
    invoke("bulk_delete_transactions", transaction_ids: ids, preview_token: token, idempotency_key: "bulk-delete")
    assert_response :success, response.body
    refute Entry.exists?(entry.id)
  end

  test "categorization preview uses local model and does not change transactions" do
    entry = entries(:transaction)
    before = entry.transaction.category_id
    invoke("preview_categorization", transaction_ids: [ entry.entryable_id ])
    assert_response :success, response.body
    assert response.parsed_body.key?("training_ready")
    assert_equal before, entry.transaction.reload.category_id
  end

  test "rejects retired posting status for writes and transaction searches" do
    assert_no_difference "Transaction.count" do
      invoke("create_transaction", { account_id: @account.id, name: "No pending state", amount: "10",
        date: Date.current.iso8601, posting_status: "pending", idempotency_key: "retired-posting" })
      assert_response :unprocessable_entity
    end
    invoke("search_transactions", { posting_status: "pending" })
    assert_response :unprocessable_entity
  end

  private
    def invoke(operation, args)
      post "/api/v1/actions/#{operation}", params: { arguments: args }, headers: headers(@key), as: :json
    end

    def headers(key)
      { "X-Api-Key" => key.display_key }
    end

    def sample_arguments(schema)
      schema = schema.deep_stringify_keys
      schema.fetch("required", []).to_h do |key|
        field = schema.fetch("properties").fetch(key)
        value = if field["enum"]
          field["enum"].first
        elsif field["type"] == "object"
          sample_arguments(field)
        elsif field["type"] == "array"
          Array.new(field.fetch("minItems", 1)) { |index| field.dig("items", "type") == "object" ? sample_arguments(field["items"]) : SecureRandom.uuid }
        elsif field["type"] == "boolean"
          true
        elsif field["type"] == "integer"
          field.fetch("minimum", 1)
        elsif field["pattern"] == Mcp::Catalog::ID[:pattern]
          SecureRandom.uuid
        elsif field["pattern"] == Mcp::Catalog::MONEY[:pattern]
          "10.00"
        elsif field["pattern"] == Mcp::Catalog::DATE[:pattern]
          Date.current.iso8601
        elsif field["pattern"] == "^[A-Z]{3}$"
          "USD"
        else
          "sample"
        end
        [ key, value ]
      end
    end
end
