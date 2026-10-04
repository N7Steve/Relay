# Consumer for jobs serialized before connector retirement.
class PlaidTransactionsRefreshPollJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled PlaidTransactionsRefreshPollJob: account connector retired")
  end
end
