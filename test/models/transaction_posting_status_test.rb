require "test_helper"

class TransactionPostingStatusTest < ActiveSupport::TestCase
  test "historical canonical and provider states no longer hide financial movements" do
    Transaction::PENDING_PROVIDERS.each do |provider|
      transaction = Transaction.create!(posting_status: "pending", extra: {
        provider => { "pending" => true, "original_description" => "Bank evidence" }
      })
      assert_not_respond_to transaction, :pending?
      assert_not_respond_to Transaction, :pending
      assert_not_respond_to Transaction, :excluding_pending
      assert_equal "Bank evidence", transaction.reload.extra.dig(provider, "original_description")
    end
  end

  test "MCP and shared REST contracts do not accept posting status or pending imports" do
    %w[create_transaction update_transaction search_transactions].each do |name|
      schema = Mcp::Catalog.fetch(name).fetch(:inputSchema)
      assert_not schema.fetch(:properties).key?(:posting_status)
      assert_raises(Api::Input::Invalid) { Mcp::Catalog.validate!(schema, { "posting_status" => "pending" }) }
    end
    schema = Mcp::Catalog.fetch("update_instance_settings").fetch(:inputSchema)
    assert_not_includes schema.to_json, "syncs_include_pending"
  end
end
