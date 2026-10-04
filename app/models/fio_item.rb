# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class FioItem < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :token, deterministic: true
    encrypts :raw_payload
    encrypts :raw_institution_payload
  end

  has_many :syncs, as: :syncable, dependent: :destroy
  belongs_to :family
  has_many :fio_accounts, dependent: :destroy
  has_one_attached :logo, dependent: :purge_later
end
