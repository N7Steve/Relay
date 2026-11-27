# A discount on a loan's rate earned by holding another product with the
# lender: payroll domiciliation, life or home insurance, a pension plan.
#
# Whether it is active only moves revisions taken from now on. A revision
# already recorded keeps the bonus points it was set with, which is how a
# lender applies them: checked at each control date, for the year that follows.
class Loan::RateBonus < ApplicationRecord
  self.table_name = "loan_rate_bonuses"

  KINDS = %w[payroll life_insurance home_insurance pension other].freeze

  belongs_to :loan

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :points, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 20 }
  validates :annual_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(points: :desc, name: :asc) }

  def self.kind_options
    KINDS.map { |kind| [ I18n.t("loans.rate_bonuses.kinds.#{kind}"), kind ] }
  end

  def annual_cost_money
    annual_cost && Money.new(annual_cost, loan.account.currency)
  end

  # Interest a year of this bonus avoids on `balance`, before its product's
  # cost. An approximation for comparison, not a schedule figure.
  def annual_saving_on(balance)
    Money.new((BigDecimal(balance.to_s) * points / 100).round(2), loan.account.currency)
  end

  # The saving net of what the linked product costs, nil without a cost.
  def annual_net_on(balance)
    return nil if annual_cost.nil?

    annual_saving_on(balance) - annual_cost_money
  end
end
