# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class TradeRepublicAccount < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :raw_positions_payload
    encrypts :raw_timeline_payload
  end

  belongs_to :trade_republic_item
  has_one :account_provider, as: :provider, dependent: :destroy
end
