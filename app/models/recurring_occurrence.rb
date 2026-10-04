# Historical Bills occurrences. Agenda uses ScheduledPayment independently.
class RecurringOccurrence < ApplicationRecord
  include Monetizable

  belongs_to :recurring_transaction
  belongs_to :family
  has_many :allocations, class_name: "RecurringAllocation",
           foreign_key: :recurring_occurrence_id, dependent: :destroy, inverse_of: :recurring_occurrence

  monetize :expected_amount, allow_nil: true

  enum :status, { scheduled: "scheduled", paid: "paid", skipped: "skipped", missed: "missed" }

  validates :original_due_on, :due_on, :currency, presence: true
  validates :expected_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
