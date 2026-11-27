# An extra repayment on a loan and what the borrower asked the lender to do
# with it: keep the term and lower the instalment (reduce_payment), or keep the
# instalment and finish sooner (reduce_term).
#
# The money is an ordinary entry on the loan account -- usually a transfer
# from the account that paid it, which `Loan::PrepaymentRecorder` can create --
# and the interest the loan posts already follows it from the day it lands.
# This record is the contractual side: the schedule, the instalment the
# Agenda expects and every projection re-size from it.
class Loan::Prepayment < ApplicationRecord
  self.table_name = "loan_prepayments"

  MODES = %w[reduce_payment reduce_term].freeze

  belongs_to :loan
  belongs_to :entry, optional: true

  # Form-only: the account the money came from, when the transfer is created
  # with the prepayment. See Loan::PrepaymentRecorder.
  attr_accessor :source_account_id

  validates :paid_on, :amount, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :fee, numericality: { greater_than_or_equal_to: 0 }
  validates :mode, inclusion: { in: MODES }
  validate :paid_within_loan_life
  validate :entry_belongs_to_loan_account

  scope :chronological, -> { order(:paid_on, :created_at) }

  def self.mode_options
    MODES.map { |mode| [ I18n.t("loans.prepayments.modes.#{mode}"), mode ] }
  end

  def amount_money
    Money.new(amount, loan.account.currency)
  end

  def fee_money
    Money.new(fee, loan.account.currency)
  end

  def to_event
    { date: paid_on, amount: amount, mode: mode }
  end

  # The movement on the loan account this prepayment was paid with: the one
  # linked, or an inflow of the same amount within a few days of its date.
  # Nil when the money has not reached the account (yet).
  def matching_entry
    return entry if entry

    loan.account.entries.where(entryable_type: "Transaction", amount: -amount)
      .where(date: (paid_on - 4)..(paid_on + 4)).order(:date).first
  end

  private
    def paid_within_loan_life
      return if paid_on.blank? || loan.nil?

      origin = loan.origination_date
      errors.add(:paid_on, :before_origination) if origin && paid_on < origin
      # On the maturity date itself there is no instalment left to reduce.
      errors.add(:paid_on, :after_maturity) if loan.maturity_date && paid_on >= loan.maturity_date
    end

    def entry_belongs_to_loan_account
      return if entry.nil? || loan.nil?

      errors.add(:entry, :invalid) unless entry.account_id == loan.account&.id
    end
end
