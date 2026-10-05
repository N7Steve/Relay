# Historical persistence only: backup and GlobalID compatibility, no publisher runtime.
class FinancekitBatch < ApplicationRecord
  belongs_to :financekit_item
  belongs_to :sync, optional: true
end
