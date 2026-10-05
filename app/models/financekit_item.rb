# Historical persistence only: backup and GlobalID compatibility, no publisher runtime.
class FinancekitItem < ApplicationRecord
  belongs_to :family
  belongs_to :user
  belongs_to :replaces_financekit_item, class_name: "FinancekitItem", optional: true
  has_many :replacement_financekit_items, class_name: "FinancekitItem",
    foreign_key: :replaces_financekit_item_id, dependent: :nullify, inverse_of: :replaces_financekit_item
  has_many :syncs, as: :syncable, dependent: :destroy
  has_many :financekit_accounts, dependent: :destroy
  has_many :financekit_account_lineages, through: :financekit_accounts
  has_many :financekit_batches, dependent: :destroy
  has_many :financekit_conflicts, dependent: :destroy
  has_many :accounts, through: :financekit_account_lineages
end
