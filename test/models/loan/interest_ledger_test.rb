require "test_helper"

class Loan::InterestLedgerTest < ActiveSupport::TestCase
  include StructuredLoanTestHelper
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    ReferenceRate.delete_all
  end

  test "posting interest makes a paid-in-full loan owe what the lender says" do
    travel_to Date.new(2026, 11, 27) do
      loan = mortgage_with_payments(interest_tracking: true)

      Account::Recalculator.new(loan.account).recalculate
      interest = loan.account.entries.where(source: Loan::InterestLedger::SOURCE).order(:date)

      assert_equal 11, interest.count
      assert_equal BigDecimal("200.65"), interest.first.amount
      assert_equal BigDecimal("2144.26"), interest.sum(:amount)
      assert interest.all? { |entry| entry.transaction.loan_interest? }
      assert_equal BigDecimal("153665.10"), loan.account.reload.balance

      split = loan.reload.repayment_split
      assert_equal BigDecimal("3834.90"), split[:principal].amount
      assert_equal BigDecimal("2144.26"), split[:interest].amount
    end
  end

  test "without posting, every instalment reads as principal, as before" do
    travel_to Date.new(2026, 11, 27) do
      loan = mortgage_with_payments(interest_tracking: false)

      Account::Recalculator.new(loan.account).recalculate

      assert_equal 0, loan.account.entries.where(source: Loan::InterestLedger::SOURCE).count
      assert_equal BigDecimal("151520.84"), loan.account.reload.balance
      assert_nil loan.repayment_split
    end
  end

  test "refreshing is idempotent, records how each entry was worked out, and clears everything when turned off" do
    travel_to Date.new(2026, 11, 27) do
      loan = mortgage_with_payments(interest_tracking: true)

      Loan::InterestLedger.new(loan).refresh!
      Loan::InterestLedger.new(loan).refresh!
      assert_equal 11, loan.account.entries.where(source: Loan::InterestLedger::SOURCE).count

      january = loan.account.entries.find_by!(source: Loan::InterestLedger::SOURCE, date: Date.new(2026, 1, 12))
      detail = january.transaction.extra["loan_interest"]
      assert_equal "2025-12-12", detail["from"]
      assert_equal 31, detail["days"]
      assert_equal "157500.0", detail["average_balance"]
      assert_equal [ [ "2025-12-12", "1.5" ] ], detail["rates"]

      loan.update!(interest_tracking: false)
      Loan::InterestLedger.new(loan.reload).refresh!
      assert_equal 0, loan.account.entries.where(source: Loan::InterestLedger::SOURCE).count
    end
  end

  test "an instalment paid a day late is accrued on its due date" do
    travel_to Date.new(2026, 2, 20) do
      loan = build_structured_mortgage(family: @family, interest_tracking: true)
      add_opening_valuation(loan)
      source = @family.accounts.create!(name: "Cuenta hipoteca", balance: 5000, currency: "EUR", accountable: Depository.new)
      Loan::ContractWrites.allow do
        Transfer::Creator.new(family: @family, source_account_id: source.id, destination_account_id: loan.account.id,
                              date: Date.new(2026, 1, 13), amount: 543.56).create
      end

      postings = Loan::InterestLedger.new(loan).postings

      on_time = Loan::Simulator.daily_interest(
        balance: BigDecimal("157500") - BigDecimal("342.91"), from: Date.new(2026, 1, 12), to: Date.new(2026, 2, 12),
        rate_for: ->(_date) { BigDecimal("1.5") }, currency_precision: 2
      )
      assert_equal [ Date.new(2026, 1, 12), Date.new(2026, 2, 12) ], postings.map(&:first)
      assert_equal on_time, postings.second.last
    end
  end

  test "an extra payment lowers the interest from the day it lands" do
    travel_to Date.new(2026, 3, 1) do
      loan = mortgage_with_payments(interest_tracking: true, through: Date.new(2026, 2, 12))
      baseline = Loan::InterestLedger.new(loan).postings.last.last

      Loan::ContractWrites.allow { create_transaction(account: loan.account, date: Date.new(2026, 1, 20), amount: -10_000, currency: "EUR", name: "Amortización") }
      reduced = Loan::InterestLedger.new(loan.reload).postings.last.last

      # 10,000 x 1.5% x 23 days / 365 = 9.45 less.
      assert_in_delta 9.45, (baseline - reduced).to_f, 0.02
    end
  end

  test "posted interest stays out of budgets and income statements" do
    travel_to Date.new(2026, 11, 27) do
      loan = mortgage_with_payments(interest_tracking: true)
      Loan::InterestLedger.new(loan).refresh!

      reportable = Transaction.budget_reportable.joins(:entry).where(entries: { account_id: loan.account.id })
      assert reportable.none?(&:loan_interest?)
      assert_includes Transaction::UNCATEGORIZED_EXCLUDED_KINDS, "loan_interest"
    end
  end

  test "posted interest cannot be edited, recategorised or deleted by hand" do
    travel_to Date.new(2026, 11, 27) do
      loan = mortgage_with_payments(interest_tracking: true)
      Loan::InterestLedger.new(loan).refresh!
      entry = loan.account.entries.find_by!(source: Loan::InterestLedger::SOURCE, date: Date.new(2026, 1, 12))

      assert_not entry.update(amount: 1)
      assert entry.errors.added?(:base, :loan_contract_closed)
      assert_not entry.transaction.update(category: categories(:food_and_drink))
      assert_not entry.destroy
      assert entry.reload.persisted?
      assert entry.update(notes: "revisado"), "a note is fine"
    end
  end

  test "an old mortgage added with today's balance is not charged for the years before" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family, interest_tracking: true)
      create_valuation(account: loan.account, date: Date.new(2026, 10, 20), amount: 153_900, currency: "EUR", kind: "opening_anchor")
      Loan::ContractWrites.allow { create_transaction(account: loan.account, date: Date.new(2026, 11, 12), amount: -543.56, currency: "EUR") }

      postings = Loan::InterestLedger.new(loan.reload).postings

      # Only the November instalment, on the balance the valuation gave for
      # the whole period it fell in (12 October - 12 November).
      assert_equal [ Date.new(2026, 11, 12) ], postings.map(&:first)
      expected = Loan::Simulator.daily_interest(balance: BigDecimal("153900"), from: Date.new(2026, 10, 12), to: Date.new(2026, 11, 12),
                                                rate_for: ->(_d) { BigDecimal("1.5") }, currency_precision: 2)
      assert_equal expected, postings.first.last
    end
  end

  test "monthly accrual posts what the schedule charges" do
    travel_to Date.new(2026, 11, 27) do
      loan = mortgage_with_payments(interest_tracking: true)
      loan.update!(interest_accrual: "monthly")

      postings = Loan::InterestLedger.new(loan.reload).postings
      schedule = loan.amortization_schedule.payments

      assert_equal schedule.first(11).map { |payment| payment.interest.amount }, postings.map(&:last)
    end
  end

  test "posting stops before a revision whose index value is unknown" do
    travel_to Date.new(2027, 2, 20) do
      loan = build_structured_mortgage(family: @family, interest_tracking: true)
      add_opening_valuation(loan)

      postings = Loan::InterestLedger.new(loan.reload).postings

      assert_equal Date.new(2026, 12, 12), postings.last.first, "no Euribor stored: nothing after the December revision"
      assert_equal Date.new(2026, 12, 12), loan.rate_reviewer.first_index_gap(as_of: Date.current)
    end
  end

  private
    def mortgage_with_payments(interest_tracking:, through: Date.new(2026, 11, 12))
      loan = build_structured_mortgage(family: @family, interest_tracking: interest_tracking)
      add_opening_valuation(loan)
      Loan::ContractWrites.allow do
        mortgage_payment_dates(through: through).each do |date|
          create_transaction(account: loan.account, date: date, amount: -543.56, currency: "EUR", name: "Cuota hipoteca")
        end
      end
      loan.reload
    end

    def add_opening_valuation(loan)
      create_valuation(account: loan.account, date: MORTGAGE_START, amount: 157_500, currency: "EUR", kind: "opening_anchor")
    end
end
