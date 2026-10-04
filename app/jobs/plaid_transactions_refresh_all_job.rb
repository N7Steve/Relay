# Consumer for jobs serialized before connector retirement.
class PlaidTransactionsRefreshAllJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled PlaidTransactionsRefreshAllJob: account connector retired")
  end
end
