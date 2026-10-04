class ClearAiCacheJob < ApplicationJob
  queue_as :low_priority

  def perform(*)
    # Preserve historical enrichment records; there is no AI cache to rebuild.
  end
end
