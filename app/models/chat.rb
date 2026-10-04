# Local persistence reader for historical conversations and family backups.
class Chat < ApplicationRecord
  belongs_to :user
  has_one :viewer, class_name: "User", foreign_key: :last_viewed_chat_id, dependent: :nullify
  has_many :messages, dependent: :destroy

  validates :title, presence: true
  scope :ordered, -> { order(created_at: :desc) }
end
