# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class FioAccount < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :raw_payload
    encrypts :raw_transactions_payload
    encrypts :iban
  end

  belongs_to :fio_item
  has_one :account_provider, as: :provider, dependent: :destroy
end
