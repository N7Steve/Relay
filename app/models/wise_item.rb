# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class WiseItem < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :token, deterministic: true
    encrypts :raw_payload
    encrypts :sca_private_key
  end

  has_many :syncs, as: :syncable, dependent: :destroy
  belongs_to :family
  has_many :wise_accounts, dependent: :destroy
end
