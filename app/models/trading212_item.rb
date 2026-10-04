# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class Trading212Item < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :api_key, deterministic: true
    encrypts :api_secret
    encrypts :raw_instruments_payload
  end

  has_many :syncs, as: :syncable, dependent: :destroy
  belongs_to :family
  has_many :trading212_accounts, dependent: :destroy
  has_one_attached :logo, dependent: :purge_later
end
