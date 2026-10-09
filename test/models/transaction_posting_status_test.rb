require "test_helper"

class TransactionPostingStatusTest < ActiveSupport::TestCase
  test "normalizes all retained pending namespaces without dropping their metadata" do
    Transaction::PENDING_PROVIDERS.each do |provider|
      extra = { provider => { "pending" => true, "original_description" => "Bank evidence" } }
      transaction = Transaction.create!(extra: extra)
      assert_equal "pending", transaction.posting_status
      assert Transaction.pending.exists?(transaction.id)
      transaction.update!(extra: { provider => extra.fetch(provider).merge("pending" => false) })
      assert_equal "posted", transaction.reload.posting_status
      assert_not transaction.pending?
      assert_equal "Bank evidence", transaction.extra.dig(provider, "original_description")
    end
  end

  test "legacy readers and scopes agree before canonical status is populated" do
    transaction = Transaction.create!
    transaction.update_columns(posting_status: nil, extra: { "plaid" => { "pending" => true } })
    assert transaction.reload.pending?
    assert Transaction.pending.exists?(transaction.id)
    assert_not Transaction.excluding_pending.exists?(transaction.id)
    transaction.update!(investment_activity_label: "Fee")
    assert_equal "pending", transaction.reload.posting_status
  end
end
