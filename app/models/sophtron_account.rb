# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class SophtronAccount < ApplicationRecord
  belongs_to :sophtron_item
  has_one :account_provider, as: :provider, dependent: :destroy
end
