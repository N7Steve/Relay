# Historical Bills match rejections retained with their series and entry links.
class RecurringMatchRejection < ApplicationRecord
  belongs_to :recurring_transaction
  belongs_to :entry
end
