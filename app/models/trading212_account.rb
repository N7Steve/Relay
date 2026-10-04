# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class Trading212Account < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :raw_positions_payload
    encrypts :raw_orders_payload
    encrypts :raw_dividends_payload
    encrypts :raw_transactions_payload
  end

  belongs_to :trading212_item
  has_one :account_provider, as: :provider, dependent: :destroy
end
