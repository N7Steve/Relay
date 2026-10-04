# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class OnchainWalletItem < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :etherscan_api_key
  end

  has_many :syncs, as: :syncable, dependent: :destroy
  belongs_to :family
  has_many :onchain_wallet_accounts, dependent: :destroy
end
