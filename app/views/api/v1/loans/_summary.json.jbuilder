# frozen_string_literal: true

# Takes loan:, as_of:.
# The headline figures of one loan, shared by the list and the detail.

account = loan.account
schedule = loan.amortization_schedule
next_payment = schedule&.payments&.find { |payment| payment.date >= as_of }
split = loan.repayment_split(as_of: as_of)
current_rate = loan.current_variable_rate(as_of)
paid_ratio = loan.balance_paid_ratio

json.currency account.currency
json.current_debt account.balance_money.as_json
json.original_principal loan.original_balance.as_json
json.repaid_ratio paid_ratio&.to_f&.round(4)
json.principal_repaid split && split[:principal].as_json
json.interest_paid split && split[:interest].as_json
json.current_rate current_rate&.to_d&.to_s("F")
json.rate_type loan.rate_type
json.structured_rate loan.structured_rate?
json.interest_tracking loan.interest_tracking?
json.payment next_payment&.payment&.as_json
json.next_payment_date next_payment&.date&.iso8601
json.next_payment_number next_payment&.number
json.term_months loan.term_months
json.remaining_months loan.remaining_months(as_of: as_of)
json.start_date loan.origination_date&.iso8601
json.payoff_date schedule&.payoff_date&.iso8601
json.total_cost loan.total_cost&.as_json
