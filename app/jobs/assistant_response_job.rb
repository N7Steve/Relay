class AssistantResponseJob < ApplicationJob
  def perform(*)
    Rails.logger.info("[RetiredAI] Ignored AssistantResponseJob")
  end
end
