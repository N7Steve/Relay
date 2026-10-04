# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class IndexaCapitalAccount < ApplicationRecord
  belongs_to :indexa_capital_item
  has_one :account_provider, as: :provider, dependent: :destroy
end
