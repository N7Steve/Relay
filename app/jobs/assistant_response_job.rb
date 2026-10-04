# Compatibility consumer for jobs queued before AI retirement.
class AssistantResponseJob < ApplicationJob
  queue_as :high_priority

  def perform(message, assistant_message = nil, backend: nil)
    return unless assistant_message

    assistant_message.with_lock do
      assistant_message.update_columns(status: "failed") if assistant_message.pending?
    end
  end
end
