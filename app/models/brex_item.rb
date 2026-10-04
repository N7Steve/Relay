# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class BrexItem < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :token, deterministic: true
    encrypts :raw_payload
  end

  has_many :syncs, as: :syncable, dependent: :destroy
  belongs_to :family
  has_many :brex_accounts, dependent: :destroy
  has_one_attached :logo, dependent: :purge_later
end
