# Persistence readers for the existing backup contract. These intentionally do
# not inherit chat behavior, STI subclasses, provider callbacks or broadcasts.
# Keep the tables until historical conversations have another recovery path.
class Family::Backup::ConversationRecords
  TYPES = {
    "Message" => %w[Message UserMessage AssistantMessage],
    "ToolCall" => %w[ToolCall ToolCall::Function]
  }.transform_values(&:freeze).freeze

  class Chat < ApplicationRecord
    self.table_name = "chats"
    belongs_to :user, class_name: "::User"
  end

  class Message < ApplicationRecord
    self.table_name = "messages"
    self.inheritance_column = :_disabled_sti
    belongs_to :chat, class_name: "::Chat"
  end

  class ToolCall < ApplicationRecord
    self.table_name = "tool_calls"
    self.inheritance_column = :_disabled_sti
    belongs_to :message, class_name: "::Message"
  end
end
