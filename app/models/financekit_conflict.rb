# Historical persistence only: backup and GlobalID compatibility, no publisher runtime.
class FinancekitConflict < ApplicationRecord
  belongs_to :family
  belongs_to :financekit_item
  belongs_to :financekit_account_lineage, optional: true
  belongs_to :financekit_transaction, optional: true
  belongs_to :resolved_by, class_name: "User", optional: true
end
