# Historical Bills price changes, including their original transaction links.
# Kept for backup recovery; no price detection or subscription intelligence runs.
class RecurringPriceChange < ApplicationRecord
  include Monetizable

  belongs_to :recurring_transaction
  belongs_to :entry, optional: true

  monetize :previous_amount, :new_amount

  enum :source, { detected: "detected", user: "user" }, prefix: :recorded_by

  validates :effective_on, :previous_amount, :new_amount, :currency, presence: true
end
