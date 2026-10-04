class Subscription < ApplicationRecord
  # Historical billing persistence only; Relay never starts or renews subscriptions.

  belongs_to :family
  validates :family_id, uniqueness: true

  enum :status, {
    incomplete: "incomplete",
    incomplete_expired: "incomplete_expired",
    trialing: "trialing",
    active: "active",
    past_due: "past_due",
    canceled: "canceled",
    unpaid: "unpaid",
    paused: "paused"
  }
end
