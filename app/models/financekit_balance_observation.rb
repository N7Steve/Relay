# Historical persistence only: backup and GlobalID compatibility, no publisher runtime.
class FinancekitBalanceObservation < ApplicationRecord
  belongs_to :financekit_account_lineage
  belongs_to :financekit_account, optional: true
end
