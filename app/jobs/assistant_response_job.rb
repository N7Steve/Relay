class AssistantResponseJob < ApplicationJob
  queue_as :high_priority

  def perform(message, assistant_message = nil, backend: nil)
    return unless Setting.ai_features_enabled?

    # Old shared jobs have no reliable transport identity after settings change.
    # Stop unmarked jobs without redirecting their history to another provider.
    if backend != "builtin"
      if assistant_message
        assistant_message.with_lock do
          if assistant_message.pending?
            # Empty pending placeholders cannot pass completed-content validation.
            assistant_message.update_columns(status: "failed")
            assistant_message.broadcast_update_to assistant_message.chat
          end
        end
      end
      message.chat.add_error(Assistant::Error.new(I18n.t("chat.errors.legacy_request_stopped")))
      return
    end

    message.request_response(assistant_message: assistant_message)
  end
end
