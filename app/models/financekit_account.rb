# Historical persistence only: backup and GlobalID compatibility, no publisher runtime.
class FinancekitAccount < ApplicationRecord
  belongs_to :financekit_item
  belongs_to :financekit_account_lineage
  has_one :account, through: :financekit_account_lineage
end
