# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class MercuryItem < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :token, deterministic: true
  end

  has_many :syncs, as: :syncable, dependent: :destroy
  belongs_to :family
  has_many :mercury_accounts, dependent: :destroy
  has_one_attached :logo, dependent: :purge_later
end
