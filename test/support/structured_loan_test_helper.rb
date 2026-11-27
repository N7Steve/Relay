# A Spanish variable mortgage with a one-year fixed opening period and three
# bonuses, shaped on a real Bankinter loan: 157,500 EUR over 360 months from
# 12 December 2025, 1.50% for the first year (2.70% before bonuses), then
# 12-month Euribor + 1.80% less 1.20 points of bonuses, revised yearly.
module StructuredLoanTestHelper
  MORTGAGE_START = Date.new(2025, 12, 12)

  def build_structured_mortgage(family:, interest_tracking: false, bonuses: true)
    account = Account.create!(
      family: family,
      name: "Hipoteca #{SecureRandom.hex(3)}",
      owner: family.users.find_by(role: "admin"),
      balance: 157_500,
      currency: "EUR",
      accountable: Loan.new(
        subtype: "mortgage",
        rate_type: "variable",
        interest_rate: 1.5,
        term_months: 360,
        start_date: MORTGAGE_START,
        initial_balance: 157_500,
        interest_accrual: "daily",
        interest_tracking: interest_tracking
      )
    )
    loan = account.loan
    loan.rate_periods.create!(starts_on: MORTGAGE_START, rate_kind: "fixed", base_rate: 2.70, review_interval_months: 12)
    loan.rate_periods.create!(starts_on: MORTGAGE_START >> 12, rate_kind: "variable", reference_index: "euribor_12m",
                              spread: 1.80, review_interval_months: 12)
    if bonuses
      loan.rate_bonuses.create!(name: "Seguro de vida", kind: "life_insurance", points: 0.6, annual_cost: 176.13)
      loan.rate_bonuses.create!(name: "Seguro de hogar", kind: "home_insurance", points: 0.3, annual_cost: 629.95)
      loan.rate_bonuses.create!(name: "Cuenta nómina", kind: "payroll", points: 0.3, annual_cost: 0)
    end
    loan.reload
  end

  def store_euribor(values)
    values.each do |month, value|
      ReferenceRate.create!(index_key: "euribor_12m", month: month, value: value, source: "ecb")
    end
  end

  def mortgage_payment_dates(through:)
    (1..360).map { |number| MORTGAGE_START >> number }.select { |date| date <= through }
  end
end
