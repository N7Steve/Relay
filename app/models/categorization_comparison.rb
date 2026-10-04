# Historical comparison ledger; no categorization provider writes new records.
class CategorizationComparison < ApplicationRecord
  belongs_to :family
  # Not named `transaction`: ActiveRecord already defines that method, and an
  # association of that name raises on load.
  belongs_to :categorized_transaction,
             class_name: "Transaction",
             foreign_key: :transaction_id,
             optional: true,
             inverse_of: false

  validates :applied_provider, :shadow_provider, presence: true

  scope :disagreements, -> { where(agreed: false) }
  scope :chronological, -> { order(:created_at) }

  # Share of sampled transactions where the two providers picked the same
  # category. Both answering "no category" counts as agreement.
  def self.agreement_rate
    total = count
    return nil if total.zero?

    (where(agreed: true).count.to_f / total * 100).round(2)
  end
end
