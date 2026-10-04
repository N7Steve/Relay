# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class PlaidAccount < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :raw_payload
    encrypts :raw_transactions_payload
    encrypts :raw_holdings_payload, previous: { attribute: :raw_investments_payload }
    encrypts :raw_liabilities_payload
  end

  belongs_to :plaid_item
  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :account, foreign_key: :plaid_account_id, dependent: :nullify
end
