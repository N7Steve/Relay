# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class KrakenAccount < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :raw_payload
    encrypts :raw_transactions_payload
  end

  belongs_to :kraken_item
  has_one :account_provider, as: :provider, dependent: :destroy
end
