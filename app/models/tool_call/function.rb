# Historical tool results retain STI identity for backup and local recovery.
class ToolCall::Function < ToolCall
  validates :function_name, :function_result, presence: true
  validates :function_arguments, presence: true, allow_blank: true
end
