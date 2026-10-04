# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class IndexaCapitalItem < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :password, deterministic: true
    encrypts :api_token, deterministic: true
  end

  has_many :syncs, as: :syncable, dependent: :destroy
  belongs_to :family
  has_many :indexa_capital_accounts, dependent: :destroy
  has_one_attached :logo, dependent: :purge_later
end
