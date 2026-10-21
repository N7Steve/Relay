# frozen_string_literal: true

require "test_helper"

class McpPendingChangesTest < ActionDispatch::IntegrationTest
  setup do
    @saved = ENV.to_h.slice("RELAY_MCP_ENABLED", "RELAY_MCP_URL", "RELAY_MCP_API_KEYS_ENABLED")
    ENV["RELAY_MCP_ENABLED"] = "true"
    ENV["RELAY_MCP_URL"] = "https://relay.example/mcp"
    ENV["RELAY_MCP_API_KEYS_ENABLED"] = "true"
    @user = users(:family_admin)
    @key = ApiKey.create!(user: @user, name: "Pending MCP", scopes: %w[read_write], source: "web", display_key: SecureRandom.hex(32))
    @account = accounts(:depository)
  end

  teardown do
    %w[RELAY_MCP_ENABLED RELAY_MCP_URL RELAY_MCP_API_KEYS_ENABLED].each { |key| ENV[key] = @saved[key] }
  end

  test "writes stage without domain changes or jobs and web approval applies dependent operations once" do
    assert_no_difference [ "Transaction.count", "Entry.count", "Api::Operation.count" ] do
      assert_no_enqueued_jobs do
        @created = propose("create_transaction", account_id: @account.id, name: "Await approval", amount: "10", date: Date.current.iso8601, idempotency_key: "pending-create")
        assert_equal "pending_approval", @created.fetch("status")
        propose("update_transaction", transaction_id: "pending:#{@created.fetch('change_id')}:transaction_id", name: "Approved name", idempotency_key: "pending-edit")
      end
    end
    set = Mcp::ChangeSet.find(@created.fetch("change_set_id"))
    sign_in @user
    get settings_pending_change_path(set)
    assert_response :success
    assert_select "form[action=?] input[name=review_token]", approve_settings_pending_change_path(set)
    assert_no_difference "Transaction.count" do
      assert_enqueued_with(job: Mcp::ApplyChangeSetJob) do
        post approve_settings_pending_change_path(set), params: { review_token: set.review_token }
      end
    end
    assert_redirected_to settings_pending_change_path(set)
    assert_difference "Transaction.count", 1 do
      Mcp::ApplyChangeSetJob.perform_now(set)
    end
    assert_equal "applied", set.reload.status
    assert_equal 2, set.overview[:applied]
    assert @account.entries.exists?(name: "Approved name")
    assert_no_difference [ "Transaction.count", "Api::Operation.count" ] do
      Mcp::ApplyChangeSetJob.perform_now(set)
    end
  end

  test "deletion remains canonical until approval and discarding has no effects" do
    entry = @account.entries.create!(name: "Keep until approval", date: Date.current, amount: 5, currency: "USD", entryable: Transaction.new)
    receipt = propose("delete_transaction", transaction_id: entry.entryable_id, idempotency_key: "pending-delete")
    assert Entry.exists?(entry.id)
    set = Mcp::ChangeSet.find(receipt.fetch("change_set_id"))
    sign_in @user
    post reject_settings_pending_change_path(set), params: { review_token: set.review_token }
    assert_equal "rejected", set.reload.status
    Mcp::ApplyChangeSetJob.perform_now(set)
    assert Entry.exists?(entry.id)
    retry_result = propose("delete_transaction", transaction_id: entry.entryable_id, idempotency_key: "pending-delete")
    assert_equal set.id, retry_result.fetch("change_set_id")
    assert_equal "rejected", retry_result.fetch("status")
    assert_equal 1, Mcp::ChangeSet.for_actor(@user).count
  end

  test "MCP cannot approve and API key does not authenticate browser approval" do
    result = propose("create_tag", name: "Unapproved", idempotency_key: "approval-boundary")
    set = Mcp::ChangeSet.find(result.fetch("change_set_id"))
    rpc("approve_pending_changes", { change_set_id: set.id })
    assert_equal(-32602, response.parsed_body.dig("error", "code"))
    post approve_settings_pending_change_path(set), params: { review_token: set.review_token }, headers: { "X-Api-Key" => @key.display_key }
    assert_response :redirect
    assert_equal "pending", set.reload.status
    assert_not @user.family.tags.exists?(name: "Unapproved")
  end

  test "review token binds the exact proposal and another user cannot inspect or approve" do
    first = propose("create_tag", name: "First", idempotency_key: "review-first")
    set = Mcp::ChangeSet.find(first.fetch("change_set_id"))
    old_token = set.review_token
    propose("create_tag", name: "Second", idempotency_key: "review-second")
    sign_in @user
    assert_no_enqueued_jobs do
      post approve_settings_pending_change_path(set), params: { review_token: old_token }
    end
    assert_equal "pending", set.reload.status
    sign_in users(:family_member)
    get settings_pending_change_path(set)
    assert_response :not_found
    post approve_settings_pending_change_path(set), params: { review_token: set.review_token }
    assert_response :not_found
    assert_equal "pending", set.reload.status
  end

  test "read scope cannot propose and retries cannot alter a stored proposal" do
    first = propose("create_tag", name: "Once", idempotency_key: "same-proposal")
    replay = propose("create_tag", name: "Once", idempotency_key: "same-proposal")
    assert_equal first, replay
    rpc("create_tag", name: "Different", idempotency_key: "same-proposal")
    assert response.parsed_body.dig("result", "isError")
    @key.update!(scopes: %w[read])
    rpc("create_tag", name: "Denied", idempotency_key: "read-only")
    assert_equal "forbidden", response.parsed_body.dig("result", "structuredContent", "error")
    assert_equal 1, Mcp::ChangeSet.find(first.fetch("change_set_id")).operations.size
  end

  test "credential revocation after approval prevents execution" do
    receipt = propose("create_tag", name: "Revoked", idempotency_key: "revocation")
    set = Mcp::ChangeSet.find(receipt.fetch("change_set_id"))
    set.approve!(actor: @user, token: set.review_token)
    @key.revoke!
    assert_no_difference "Tag.count" do
      Mcp::ApplyChangeSetJob.perform_now(set)
    end
    assert_equal "failed", set.reload.status
    assert_equal 0, set.overview[:applied]
    assert_equal "Api::Access::Forbidden", set.operations.first.fetch("error")
  end

  test "changed account permissions stop application and failure never rolls back already completed work" do
    first = propose("update_profile", first_name: "Applied first", idempotency_key: "partial-first")
    propose("create_transaction", account_id: @account.id, name: "Not permitted", date: Date.current.iso8601, amount: "2", idempotency_key: "partial-second")
    propose("create_tag", name: "Never reached", idempotency_key: "partial-third")
    set = Mcp::ChangeSet.find(first.fetch("change_set_id"))
    set.approve!(actor: @user, token: set.review_token)
    @account.update!(owner: users(:family_member))
    @account.account_shares.where(user: @user).delete_all
    Mcp::ApplyChangeSetJob.perform_now(set)
    assert_equal "failed", set.reload.status
    assert_equal "Applied first", @user.reload.first_name
    assert_not @account.entries.exists?(name: "Not permitted")
    assert_not @user.family.tags.exists?(name: "Never reached")
    assert_equal %w[applied failed pending], set.operations.map { |row| row.fetch("status") }
    assert_no_difference "Tag.count" do
      Mcp::ApplyChangeSetJob.perform_now(set)
    end
  end

  test "references cannot point outside the proposal and schema limits still apply" do
    rpc("update_transaction", transaction_id: "pending:#{SecureRandom.uuid}:transaction_id", name: "No source", idempotency_key: "bad-ref")
    assert response.parsed_body.dig("result", "isError")
    rpc("create_tag", name: "Wrong", unexpected: true, idempotency_key: "bad-schema")
    assert response.parsed_body.dig("result", "isError")
    assert_empty Mcp::ChangeSet.for_actor(@user)
  end

  test "all write tool contracts advertise proposals and there is no approval tool" do
    tools = Mcp::ProposalCatalog.definitions
    Mcp::Catalog.all.each_value do |domain|
      next if domain.dig(:annotations, :readOnlyHint)
      tool = tools.find { |item| item[:name] == domain[:name] }
      assert_includes tool[:description], "Propose only"
      assert_equal %w[status change_set_id change_id], tool[:outputSchema][:required]
    end
    assert tools.any? { |tool| tool[:name] == "get_pending_changes" }
    assert_not tools.any? { |tool| tool[:name].match?(/approve.*change|reject.*change/) }
  end

  test "a dependent create edit delete sequence applies only after approval" do
    created = propose("create_transaction", account_id: @account.id, name: "Temporary proposal", amount: "7", date: Date.current.iso8601, idempotency_key: "chain-create")
    reference = "pending:#{created.fetch('change_id')}:transaction_id"
    propose("update_transaction", transaction_id: reference, name: "Edited proposal", idempotency_key: "chain-edit")
    propose("delete_transaction", transaction_id: reference, idempotency_key: "chain-delete")
    set = Mcp::ChangeSet.find(created.fetch("change_set_id"))
    assert_no_difference "Transaction.count" do
      set.approve!(actor: @user, token: set.review_token)
      set.apply!
    end
    assert_equal "applied", set.reload.status
    assert_equal 3, set.overview[:applied]
    assert_not @account.entries.exists?(name: [ "Temporary proposal", "Edited proposal" ])
  end

  test "references in arrays resolve and canonical reads exclude pending creations" do
    created = propose("create_tag", name: "Pending label", idempotency_key: "tag-create")
    propose("create_transaction", account_id: @account.id, name: "Tagged proposal", amount: "5", date: Date.current.iso8601,
      tag_ids: [ "pending:#{created.fetch('change_id')}:id" ], idempotency_key: "tagged-transaction")
    rpc("search_transactions", search: "Tagged proposal")
    assert_empty response.parsed_body.dig("result", "structuredContent", "data")
    set = Mcp::ChangeSet.find(created.fetch("change_set_id"))
    set.approve!(actor: @user, token: set.review_token)
    set.apply!
    assert_equal "applied", set.reload.status
    assert_equal [ "Pending label" ], @account.entries.find_by!(name: "Tagged proposal").transaction.tags.pluck(:name)
  end

  test "revocation before approval refuses to enqueue and pending inspection reveals no arguments" do
    receipt = propose("update_profile", first_name: "Hidden proposal text", idempotency_key: "pre-approval-revoke")
    rpc("get_pending_changes", {})
    assert_equal 1, response.parsed_body.dig("result", "structuredContent", "data").size
    assert_not_includes response.body, "Hidden proposal text"
    set = Mcp::ChangeSet.find(receipt.fetch("change_set_id"))
    @key.revoke!
    sign_in @user
    assert_no_enqueued_jobs do
      post approve_settings_pending_change_path(set), params: { review_token: set.review_token }
    end
    assert_equal "pending", set.reload.status
  end

  test "a deferred destructive preview is evaluated after approval and can feed its signed token to a later write" do
    entry = @account.entries.create!(name: "Deferred bulk delete", date: Date.current, amount: 5, currency: "USD", entryable: Transaction.new)
    preview = propose("preview_bulk_delete_transactions", transaction_ids: [ entry.entryable_id ], defer_until_approval: true, idempotency_key: "deferred-preview")
    propose("bulk_delete_transactions", transaction_ids: [ entry.entryable_id ],
      preview_token: "pending:#{preview.fetch('change_id')}:preview_token", idempotency_key: "deferred-delete")
    assert Entry.exists?(entry.id)
    set = Mcp::ChangeSet.find(preview.fetch("change_set_id"))
    travel 2.days do
      set.approve!(actor: @user, token: set.review_token)
      set.apply!
    end
    assert_equal "applied", set.reload.status
    assert_not Entry.exists?(entry.id)
    assert_equal %w[applied applied], set.operations.map { |row| row.fetch("status") }
  end

  test "reads using earlier pending results are deferred without touching canonical records" do
    created = propose("create_transaction", account_id: @account.id, name: "Pending read", amount: "5", date: Date.current.iso8601, idempotency_key: "read-chain-create")
    read = propose("get_transaction", transaction_id: "pending:#{created.fetch('change_id')}:transaction_id")
    assert_equal created.fetch("change_set_id"), read.fetch("change_set_id")
    set = Mcp::ChangeSet.find(created.fetch("change_set_id"))
    set.approve!(actor: @user, token: set.review_token)
    set.apply!
    assert_equal "applied", set.reload.status
    assert_equal "Pending read", set.operations.last.dig("result", "name")
  end

  private
    def propose(name, arguments)
      rpc(name, arguments)
      result = response.parsed_body.fetch("result")
      assert_not result["isError"], response.body
      result.fetch("structuredContent")
    end

    def rpc(name, arguments)
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } },
        headers: { "X-Api-Key" => @key.display_key, "Accept" => "application/json, text/event-stream", "MCP-Protocol-Version" => "2025-11-25" }, as: :json
    end
end
