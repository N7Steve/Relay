# Historical STI and tool results remain readable without provider callbacks.
class Message < ApplicationRecord
  belongs_to :chat
  has_many :tool_calls, dependent: :destroy

  enum :status, { pending: "pending", complete: "complete", failed: "failed" }
  validates :content, presence: true, unless: :pending?
  scope :ordered, -> { order(created_at: :asc) }
end
