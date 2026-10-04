# Consumer for jobs serialized before connector retirement.
class PlaidTransactionsRefreshJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled PlaidTransactionsRefreshJob: account connector retired")
  end
end
