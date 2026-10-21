# frozen_string_literal: true

require "test_helper"

class Api::V1::AccessBoundariesTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:family_admin)
    @actor = users(:family_member)
    @key = ApiKey.create!(user: @actor, name: "Boundaries", scopes: [ "read_write" ], display_key: ApiKey.generate_secure_key)
    @account = accounts(:depository)
    @share = account_shares(:depository_shared_with_member)
    @entry = @account.entries.create!(name: "Private movement", date: Date.current, amount: 12, currency: "USD", entryable: Transaction.new)
    @valuation = @account.entries.create!(name: "Private valuation", date: Date.current - 3.days, amount: 120, currency: "USD", entryable: Valuation.new)
    @investment = accounts(:investment)
    @trade = @investment.entries.create!(name: "Private trade", date: Date.current, amount: 10, currency: "USD",
      entryable: Trade.new(security: securities(:aapl), qty: 1, price: 10, currency: "USD"))
  end

  test "private account rows cannot be read by ID or listed even within the same family" do
    @share.destroy!
    [ "/api/v1/transactions/#{@entry.entryable_id}", "/api/v1/valuations/#{@valuation.id}", "/api/v1/trades/#{@trade.entryable_id}" ].each do |url|
      get url, headers: api_headers(@key)
      assert_response :not_found
    end
    [ [ "transactions", @entry.entryable_id ], [ "valuations", @valuation.id ], [ "trades", @trade.entryable_id ] ].each do |resource, id|
      get "/api/v1/#{resource}", headers: api_headers(@key)
      assert_response :success
      assert_not_includes response.body, id
    end
  end

  test "read only and annotation shares cannot change amounts or delete transactions" do
    %w[read_only read_write].each do |permission|
      @share.update!(permission: permission)
      patch api_v1_transaction_url(@entry.entryable_id), params: { transaction: { amount: 999 } }, headers: api_headers(@key)
      assert_response :forbidden
      assert_equal 12, @entry.reload.amount
      assert_no_difference "Entry.count" do
        delete api_v1_transaction_url(@entry.entryable_id), headers: api_headers(@key)
      end
      assert_response :forbidden
    end
  end

  test "annotation share can edit notes but not name or import protection" do
    @share.update!(permission: "read_write")
    patch api_v1_transaction_url(@entry.entryable_id), params: { transaction: { notes: "Reviewed" } }, headers: api_headers(@key)
    assert_response :success
    assert_equal "Reviewed", @entry.reload.notes
    %w[name user_modified].each do |field|
      patch api_v1_transaction_url(@entry.entryable_id), params: { transaction: { field => "changed" } }, headers: api_headers(@key)
      assert_response :forbidden
    end
  end

  test "full control share permits financial edits" do
    patch api_v1_transaction_url(@entry.entryable_id), params: { transaction: { amount: "12.34" } }, headers: api_headers(@key)
    assert_response :success
    assert_equal BigDecimal("12.34"), @entry.reload.amount
  end

  test "an administrator cannot read a private account owned by another member" do
    @investment.update!(owner: @actor)
    @key.update!(user: @owner)
    get api_v1_trade_url(@trade.entryable_id), headers: api_headers(@key)
    assert_response :not_found
    patch api_v1_trade_url(@trade.entryable_id), params: { trade: { price: 20 } }, headers: api_headers(@key)
    assert_response :not_found
  end

  test "another family and a guest do not gain family operation authority" do
    @key.update!(user: users(:empty))
    get api_v1_valuation_url(@valuation), headers: api_headers(@key)
    assert_response :not_found
    @key.update!(user: @actor)
    @actor.update!(role: :guest)
    get api_v1_imports_url, headers: api_headers(@key)
    assert_response :forbidden
  end

  test "read credential cannot mutate an otherwise writable account" do
    @key.update!(scopes: [ "read" ])
    patch api_v1_transaction_url(@entry.entryable_id), params: { transaction: { notes: "changed" } }, headers: api_headers(@key)
    assert_response :forbidden
    post api_v1_valuations_url, params: { valuation: { account_id: @account.id, amount: 1, date: Date.current.iso8601 } }, headers: api_headers(@key)
    assert_response :forbidden
    assert_nil @entry.reload.notes
  end

  test "money input keeps decimal precision instead of passing through float" do
    patch api_v1_transaction_url(@entry.entryable_id), params: { transaction: { amount: "900719925474.1234" } }, headers: api_headers(@key)
    assert_response :success
    assert_equal BigDecimal("900719925474.1234"), @entry.reload.amount
  end

  test "read only shares cannot create update or reconcile valuations" do
    @share.update!(permission: "read_only")
    post api_v1_valuations_url, params: { valuation: { account_id: @account.id, amount: 999, date: Date.current.iso8601 } }, headers: api_headers(@key)
    assert_response :forbidden
    patch api_v1_valuation_url(@valuation), params: { valuation: { notes: "changed" } }, headers: api_headers(@key)
    assert_response :forbidden
    assert_nil @valuation.reload.notes
  end

  test "trade writes require full control and the share is rechecked on every request" do
    @investment.share_with!(@actor, permission: "read_only")
    get api_v1_trade_url(@trade.entryable_id), headers: api_headers(@key)
    assert_response :success
    patch api_v1_trade_url(@trade.entryable_id), params: { trade: { notes: "changed" } }, headers: api_headers(@key)
    assert_response :forbidden
    delete api_v1_trade_url(@trade.entryable_id), headers: api_headers(@key)
    assert_response :forbidden
    post api_v1_trades_url, params: { trade: { account_id: @investment.id, date: Date.current.iso8601, type: "buy", qty: 1, price: 10, security_id: securities(:aapl).id } }, headers: api_headers(@key)
    assert_response :forbidden
    @investment.account_shares.find_by!(user: @actor).destroy!
    get api_v1_trade_url(@trade.entryable_id), headers: api_headers(@key)
    assert_response :not_found
  end

  test "foreign family category merchant and tag references are rejected atomically" do
    foreign = families(:empty)
    category = foreign.categories.create!(name: "Foreign category", color: "#000000")
    tag = foreign.tags.create!(name: "Foreign tag", color: "#000000")
    merchant = foreign.merchants.create!(name: "Foreign merchant")
    [ { category_id: category.id }, { tag_ids: [ tag.id ] }, { merchant_id: merchant.id } ].each do |attributes|
      patch api_v1_transaction_url(@entry.entryable_id), params: { transaction: attributes.merge(notes: "must rollback") }, headers: api_headers(@key)
      assert_response :unprocessable_entity
      assert_nil @entry.reload.notes
    end
  end

  test "family wide operations are restricted to administrators without enqueueing work" do
    assert_no_enqueued_jobs do
      get api_v1_imports_url, headers: api_headers(@key)
      assert_response :forbidden
      post api_v1_imports_url, params: { type: "TransactionImport" }, headers: api_headers(@key)
      assert_response :forbidden
      post preflight_api_v1_imports_url, params: {}, headers: api_headers(@key)
      assert_response :forbidden
      post api_v1_import_sessions_url, params: { type: "RelayImport" }, headers: api_headers(@key)
      assert_response :forbidden
      post api_v1_sync_job_url, headers: api_headers(@key)
      assert_response :forbidden
      get api_v1_provider_connections_url, headers: api_headers(@key)
      assert_response :forbidden
    end
  end

  test "inaccessible transfer counterpart is not serialized and cannot be edited indirectly" do
    outflow = @account.entries.create!(name: "Outflow", date: Date.current, amount: 20, currency: "USD", entryable: Transaction.new)
    inflow = @investment.entries.create!(name: "Inflow", date: Date.current, amount: -20, currency: "USD", entryable: Transaction.new)
    transfer = Transfer.create!(outflow_transaction: outflow.transaction, inflow_transaction: inflow.transaction)
    entry = transfer.outflow_transaction.entry
    get api_v1_transaction_url(entry.entryable_id), headers: api_headers(@key)
    assert_response :success
    assert_nil response.parsed_body["transfer"]
    patch api_v1_transaction_url(entry.entryable_id), params: { transaction: { amount: 50 } }, headers: api_headers(@key)
    assert_response :forbidden
    delete api_v1_transaction_url(entry.entryable_id), headers: api_headers(@key)
    assert_response :forbidden
  end

  test "invalid dates and non finite or malformed decimal input are client errors" do
    [ { start_date: "yesterday" }, { min_amount: "12oops" }, { max_amount: "NaN" } ].each do |query|
      get api_v1_transactions_url, params: query, headers: api_headers(@key)
      assert_response :unprocessable_entity
    end
    [ "Infinity", "12oops", "NaN" ].each do |amount|
      patch api_v1_transaction_url(@entry.entryable_id), params: { transaction: { amount: amount } }, headers: api_headers(@key)
      assert_response :unprocessable_entity
      assert_equal 12, @entry.reload.amount
    end
  end

  test "inactive user cannot read or write even if the key remains stored" do
    @actor.update_column(:active, false)
    get api_v1_transactions_url, headers: api_headers(@key)
    assert_response :unauthorized
    patch api_v1_transaction_url(@entry.entryable_id), params: { transaction: { amount: 20 } }, headers: api_headers(@key)
    assert_response :unauthorized
  end

  test "family sync metadata and insights do not reveal private account activity" do
    family_sync = Sync.create!(syncable: @owner.family)
    account_sync = Sync.create!(syncable: @account, parent: family_sync)
    get api_v1_sync_url(family_sync), headers: api_headers(@key)
    assert_response :not_found
    get api_v1_sync_url(account_sync), headers: api_headers(@key)
    assert_response :success
    assert_equal account_sync.id, response.parsed_body.dig("data", "id")
    assert_nil response.parsed_body.dig("data", "parent_id")
    @actor.update!(preferences: @actor.preferences.merge("preview_features_enabled" => true))
    get api_v1_insights_url, headers: api_headers(@key)
    assert_response :forbidden
  end
end
