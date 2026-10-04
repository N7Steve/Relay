# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class SimplefinAccount < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :raw_payload
    encrypts :raw_transactions_payload
    encrypts :raw_holdings_payload
  end

  belongs_to :simplefin_item
  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :account, foreign_key: :simplefin_account_id, dependent: :nullify
end
