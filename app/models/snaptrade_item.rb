# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class SnaptradeItem < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :client_id, deterministic: true
    encrypts :consumer_key, deterministic: true
    encrypts :snaptrade_user_secret
    encrypts :oauth_access_token
    encrypts :oauth_refresh_token
  end

  has_many :syncs, as: :syncable, dependent: :destroy
  belongs_to :family
  has_many :snaptrade_accounts, dependent: :destroy
  has_one_attached :logo, dependent: :purge_later
end
