require "test_helper"
require "ostruct"

class Account::SyncerTest < ActiveSupport::TestCase
  test "post-sync auto matches only transfers touching the synced account" do
    account = accounts(:depository)

    account.family.expects(:auto_match_transfers!).with(account: account).once

    Account::Syncer.new(account).perform_post_sync
  end

  test "applies IBKR historical balance overrides after materialization" do
    family = families(:empty)
    account = family.accounts.create!(
      name: "IBKR Brokerage",
      balance: 0,
      cash_balance: 0,
      currency: "CHF",
      accountable: Investment.new(subtype: "brokerage")
    )
    account.update!(reverse_balance_history: true, imported_balance_history: [ { report_date: "2026-05-07", total: "3351" } ])

    Balance::Materializer.any_instance.expects(:materialize_balances).once
    Account::ImportedBalanceHistory.any_instance.expects(:sync!).once

    Account::Syncer.new(account).perform_sync(OpenStruct.new(window_start_date: nil))
  end
end
