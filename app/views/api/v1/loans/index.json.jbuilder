# frozen_string_literal: true

json.as_of @as_of.iso8601
json.loans @accounts do |account|
  json.account do
    json.partial! "api/v1/accounts/account", account: account
  end
  json.summary do
    json.partial! "api/v1/loans/summary", loan: account.loan, as_of: @as_of
  end
end
