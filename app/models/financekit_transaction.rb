# Historical persistence only: backup and GlobalID compatibility, no publisher runtime.
class FinancekitTransaction < ApplicationRecord
  belongs_to :financekit_account_lineage
  belongs_to :financekit_account, optional: true
  belongs_to :entry, optional: true
  has_many :financekit_conflicts, dependent: :nullify
end
