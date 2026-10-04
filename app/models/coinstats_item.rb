# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class CoinstatsItem < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :api_key, deterministic: true if encryption_ready?
  end

  has_many :syncs, as: :syncable, dependent: :destroy
  belongs_to :family
  has_many :coinstats_accounts, dependent: :destroy
  has_one_attached :logo, dependent: :purge_later
end
