class WorkerAiHealthCheckJob < ApplicationJob
  queue_as :default

  def perform(*)
    # Retired probe: consume serialized jobs without contacting a provider.
  end
end
