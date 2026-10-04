# Consumer for jobs serialized before connector retirement.
class SophtronInitialLoadJob < ApplicationJob
  def perform(*args, **kwargs)
    Rails.logger.info("Cancelled SophtronInitialLoadJob: account connector retired")
  end
end
