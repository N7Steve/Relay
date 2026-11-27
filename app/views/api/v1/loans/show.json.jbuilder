# frozen_string_literal: true

loan = @account.loan
as_of = @as_of
schedule = loan.amortization_schedule
next_payment = schedule&.payments&.find { |payment| payment.date >= as_of }
# The instalment due next, split into what it repays, costs and insures.
breakdown = next_payment && loan.payment_breakdown(payment_number: next_payment.number, as_of: as_of)

json.as_of as_of.iso8601

json.account do
  json.partial! "api/v1/accounts/account", account: @account
end

json.summary do
  json.partial! "api/v1/loans/summary", loan: loan, as_of: as_of
end

if breakdown
  json.current_instalment do
    json.number breakdown[:number]
    json.date breakdown[:date].iso8601
    json.total breakdown[:total].as_json
    json.principal breakdown[:principal].as_json
    json.interest breakdown[:interest].as_json
    json.insurance breakdown[:insurance].as_json
    json.ratios do
      json.principal breakdown[:ratios][:principal].round(4)
      json.interest breakdown[:ratios][:interest].round(4)
      json.insurance breakdown[:ratios][:insurance].round(4)
    end
  end
else
  json.current_instalment nil
end

json.rate do
  json.structured loan.structured_rate?
  json.current_rate loan.current_variable_rate(as_of)&.to_d&.to_s("F")

  if loan.structured_rate?
    reviewer = loan.rate_reviewer
    current = reviewer.revision_on(as_of, as_of: as_of)
    upcoming = reviewer.next_revision(as_of: as_of)

    if current
      json.current do
        json.partial! "api/v1/loans/revision", revision: current, as_of: as_of
      end
    else
      json.current nil
    end

    if upcoming
      # The first instalment sized at the new rate, as the web Rates tab
      # quotes it.
      first_payment_after = loan.payment_dates.find { |date| date > upcoming.effective_on }
      new_payment = first_payment_after && loan.payment_due_on(first_payment_after)

      json.next_revision do
        json.partial! "api/v1/loans/revision", revision: upcoming, as_of: as_of
        json.new_payment new_payment&.as_json
        json.new_payment_date new_payment ? first_payment_after.iso8601 : nil
      end
    else
      json.next_revision nil
    end

    # History, anything due and not recorded yet, and the next one ahead.
    shown = reviewer.timeline(as_of: as_of).select do |revision|
      revision.persisted? || revision.effective_on <= as_of || revision.equal?(upcoming)
    end
    json.revisions shown do |revision|
      json.partial! "api/v1/loans/revision", revision: revision, as_of: as_of
    end

    json.periods loan.rate_periods.to_a do |period|
      json.starts_on period.starts_on.iso8601
      json.rate_kind period.rate_kind
      json.base_rate period.base_rate&.to_d&.to_s("F")
      json.reference_index period.reference_index
      json.reference_index_name period.reference_index && t("reference_rates.indexes.#{period.reference_index}", default: period.reference_index.to_s)
      json.spread period.spread&.to_d&.to_s("F")
      json.floor_rate period.floor_rate&.to_d&.to_s("F")
      json.review_interval_months period.review_interval_months
      json.applies_bonuses period.applies_bonuses
      json.lender_name period.lender_name
    end

    json.bonuses loan.rate_bonuses.ordered.to_a do |bonus|
      json.name bonus.name
      json.kind bonus.kind
      json.points bonus.points.to_d.to_s("F")
      json.active bonus.active?
      json.annual_cost bonus.annual_cost_money&.as_json
    end
  else
    json.current nil
    json.next_revision nil
    json.revisions []
    json.periods []
    json.bonuses []
  end
end

if schedule
  projection = loan.payoff_projection(as_of: as_of)

  json.schedule do
    json.currency schedule.currency
    json.re_amortising schedule.re_amortising?
    json.opening_payment schedule.periodic_payment.as_json
    json.total_interest schedule.total_interest.as_json
    json.total_paid schedule.total_paid.as_json
    json.payoff_date schedule.payoff_date&.iso8601
    json.projected_payoff_date projection.payoff_date&.iso8601
    # Every contractual instalment, oldest first. Amounts are decimal strings
    # in the schedule's currency; `past` marks the ones due on or before as_of.
    json.payments schedule.payments do |payment|
      json.number payment.number
      json.date payment.date.iso8601
      json.payment payment.payment.amount.to_d.to_s("F")
      json.principal payment.principal.amount.to_d.to_s("F")
      json.interest payment.interest.amount.to_d.to_s("F")
      json.prepayment payment.prepayment.amount.to_d.to_s("F")
      json.ending_balance payment.ending_balance.amount.to_d.to_s("F")
      json.past payment.date <= as_of
    end
  end
else
  json.schedule nil
end
