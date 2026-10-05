class Account::Syncer
  attr_reader :account

  def initialize(account)
    @account = account
  end

  def perform_sync(sync)
    Rails.logger.info("Processing balances (#{account.reverse_balance_history? ? 'reverse' : 'forward'})")
    Account::Recalculator.new(account).recalculate(window_start_date: sync.window_start_date)
  end

  def perform_post_sync
    ExternalAccess.locally { account.family.auto_match_transfers!(account: account) }
  end
end
