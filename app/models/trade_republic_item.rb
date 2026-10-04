# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class TradeRepublicItem < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :phone_number, deterministic: true
    encrypts :session_blob
    encrypts :pending_login_state
  end

  has_many :syncs, as: :syncable, dependent: :destroy
  belongs_to :family
  has_many :trade_republic_accounts, dependent: :destroy
end
