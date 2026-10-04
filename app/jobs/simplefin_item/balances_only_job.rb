# Consumer for jobs serialized before connector retirement.
class SimplefinItem::BalancesOnlyJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled SimplefinItem::BalancesOnlyJob: account connector retired")
  end
end
