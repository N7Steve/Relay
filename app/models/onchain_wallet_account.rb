# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class OnchainWalletAccount < ApplicationRecord
  belongs_to :onchain_wallet_item
  has_one :account_provider, as: :provider, dependent: :destroy
end
