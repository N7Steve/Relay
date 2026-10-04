# Historical persistence only: backup and GlobalID compatibility, no connector runtime.
class IbkrAccount < ApplicationRecord
  include Encryptable

  if encryption_ready?
    encrypts :raw_holdings_payload
    encrypts :raw_activities_payload
    encrypts :raw_cash_report_payload
    encrypts :raw_equity_summary_payload
  end

  belongs_to :ibkr_item
  has_one :account_provider, as: :provider, dependent: :destroy


  def current_account
    account_provider&.account
  end
end
