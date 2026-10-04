# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class SimplefinItem < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :access_url, deterministic: true
    encrypts :raw_payload
    encrypts :raw_institution_payload
  end

  has_many :syncs, as: :syncable, dependent: :destroy
  belongs_to :family
  has_many :simplefin_accounts, dependent: :destroy
  has_one_attached :logo, dependent: :purge_later
  def accounts
    simplefin_accounts.includes(:account, account_provider: :account).flat_map do |provider_account|
      [ provider_account.account_provider&.account, provider_account.account ].compact
    end.uniq
  end
end
