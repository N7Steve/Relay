# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class SophtronItem < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :user_id, deterministic: true
    encrypts :access_key, deterministic: true
  end

  has_many :syncs, as: :syncable, dependent: :destroy
  belongs_to :family
  has_many :sophtron_accounts, dependent: :destroy
  has_one_attached :logo, dependent: :purge_later
end
