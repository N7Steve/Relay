class EnhanceProviderMerchantsJob < ApplicationJob
  queue_as :medium_priority

  def perform(family)
    Rails.cache.delete("enhance_provider_merchants:#{family.id}")
  end
end
