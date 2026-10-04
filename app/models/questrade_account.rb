# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class QuestradeAccount < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :raw_payload
    encrypts :raw_holdings_payload
    encrypts :raw_activities_payload
    encrypts :raw_balances_payload
  end

  belongs_to :questrade_item
  has_one :account_provider, as: :provider, dependent: :destroy
end
