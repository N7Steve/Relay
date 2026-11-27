require "test_helper"

class Loan::PrepaymentTest < ActiveSupport::TestCase
  include StructuredLoanTestHelper
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    ReferenceRate.delete_all
  end

  test "shortening the term keeps the instalment and ends the loan sooner" do
    base = simulate
    shorter = simulate(prepayments: [ { date: Date.new(2026, 6, 12), amount: 20_000, mode: :reduce_term } ])

    assert_equal BigDecimal("543.56"), shorter.payments[7][:payment_amount]
    assert_operator shorter.payments.size, :<, base.payments.size - 40
    assert_operator shorter.total_interest, :<, base.total_interest - 10_000
    assert_equal BigDecimal("20000"), shorter.payments[6][:prepayment]
  end

  test "lowering the instalment keeps the end date" do
    base = simulate
    lower = simulate(prepayments: [ { date: Date.new(2026, 6, 12), amount: 20_000, mode: :reduce_payment } ])

    assert_equal base.payments.last[:payment_date], lower.payments.last[:payment_date]
    assert_operator lower.payments[7][:payment_amount], :<, BigDecimal("480")
    # Shortening saves more interest than lowering the instalment.
    shorter = simulate(prepayments: [ { date: Date.new(2026, 6, 12), amount: 20_000, mode: :reduce_term } ])
    assert_operator shorter.total_interest, :<, lower.total_interest
  end

  test "a prepayment mid-period is charged on the balance each day actually carried" do
    result = simulate(prepayments: [ { date: Date.new(2026, 1, 22), amount: 50_000, mode: :reduce_term } ])
    rate = ->(_date) { BigDecimal("1.5") }

    opening = result.payments.first[:ending_balance]
    expected = (
      Loan::Simulator.accrued_interest(balance: opening, from: Date.new(2026, 1, 12), to: Date.new(2026, 1, 22), rate_for: rate) +
      Loan::Simulator.accrued_interest(balance: opening - 50_000, from: Date.new(2026, 1, 22), to: Date.new(2026, 2, 12), rate_for: rate)
    ).round(2)

    assert_equal expected, result.payments.second[:interest_payment]
    assert_equal opening, result.payments.second[:beginning_balance]
  end

  test "a revision after a shortened term re-sizes over the shorter term" do
    rate = ->(date) { date < Date.new(2026, 12, 12) ? BigDecimal("1.5") : BigDecimal("3.84") }
    shorter = simulate(rate: rate, prepayments: [ { date: Date.new(2026, 6, 12), amount: 20_000, mode: :reduce_term } ])
    payments = shorter.payments
    resized = payments[12][:payment_amount]

    assert_operator resized, :>, BigDecimal("543.56")
    # Level to the new, earlier end: every later instalment but the last matches.
    assert payments[12...-1].all? { |row| row[:payment_amount] == resized }
    assert_operator payments.last[:payment_date], :<, Date.new(2055, 12, 12) << 24
  end

  test "a revision landing with a shorten-the-term prepayment keeps the revised instalment" do
    rate = ->(date) { date < Date.new(2026, 12, 12) ? BigDecimal("1.5") : BigDecimal("3.84") }
    base = simulate(rate: rate)
    shorter = simulate(rate: rate, prepayments: [ { date: Date.new(2026, 12, 12), amount: 20_000, mode: :reduce_term } ])

    assert_equal base.payments[12][:payment_amount], shorter.payments[12][:payment_amount]
    assert_operator shorter.payments.size, :<, base.payments.size - 40
  end

  test "recording a prepayment from an account creates the transfer and re-sizes the schedule" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)
      source = @family.accounts.create!(name: "Cuenta hipoteca", balance: 30_000, currency: "EUR", accountable: Depository.new)

      prepayment = Loan::PrepaymentRecorder.new(loan, source_account: source)
        .record(paid_on: Date.new(2026, 11, 20), amount: 10_000, mode: "reduce_payment", fee: 0)

      assert prepayment.persisted?
      assert_equal loan.account, prepayment.entry.account
      assert_equal BigDecimal("-10000"), prepayment.entry.amount
      assert prepayment.entry.transaction.transfer?
      assert_operator loan.reload.payment_due_on(Date.new(2026, 12, 12)).amount, :<, BigDecimal("543.56")
    end
  end

  test "without a source account an existing movement is linked" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)
      movement = create_transaction(account: loan.account, date: Date.new(2026, 11, 19), amount: -5_000, currency: "EUR")

      prepayment = Loan::PrepaymentRecorder.new(loan).record(paid_on: Date.new(2026, 11, 20), amount: 5_000, mode: "reduce_term")

      assert_equal movement, prepayment.entry
    end
  end

  test "a prepayment before the loan started is rejected" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)

      prepayment = Loan::PrepaymentRecorder.new(loan).record(paid_on: Date.new(2025, 1, 1), amount: 1_000, mode: "reduce_term")

      assert_not prepayment.persisted?
      assert prepayment.errors.added?(:paid_on, :before_origination)
    end
  end

  test "an extra payment near a due date is not mistaken for the instalment" do
    travel_to Date.new(2026, 3, 1) do
      loan = build_structured_mortgage(family: @family, interest_tracking: true)
      create_valuation(account: loan.account, date: MORTGAGE_START, amount: 157_500, currency: "EUR", kind: "opening_anchor")
      source = @family.accounts.create!(name: "Ahorro", balance: 30_000, currency: "EUR", accountable: Depository.new)
      Transfer::Creator.new(family: @family, source_account_id: source.id, destination_account_id: loan.account.id,
                            date: Date.new(2026, 1, 14), amount: 10_000).create

      postings = Loan::InterestLedger.new(loan.reload).postings
      february = postings.find { |date, _| date == Date.new(2026, 2, 12) }.last

      # The 10,000 counts from 14 January, not from the 12th.
      expected = (
        Loan::Simulator.accrued_interest(balance: BigDecimal("157700.65"), from: Date.new(2026, 1, 12), to: Date.new(2026, 1, 14), rate_for: ->(_d) { BigDecimal("1.5") }) +
        Loan::Simulator.accrued_interest(balance: BigDecimal("147700.65"), from: Date.new(2026, 1, 14), to: Date.new(2026, 2, 12), rate_for: ->(_d) { BigDecimal("1.5") })
      ).round(2)
      assert_equal expected, february
    end
  end

  private
    def simulate(prepayments: [], rate: ->(_date) { BigDecimal("1.5") })
      Loan::Simulator.new(
        starting_balance: 157_500,
        accrual_start_date: MORTGAGE_START,
        payment_schedule: (1..360).map { |number| MORTGAGE_START >> number },
        accrual_rate_for: rate,
        currency_precision: 2,
        day_count: :actual_365,
        payment_sizing: :period_opening,
        prepayments: prepayments
      ).run
    end
end
