require "test_helper"

# Daily accrual, structured rate periods and their revisions, checked against
# the figures a Spanish lender's statement shows for the same mortgage.
class Loan::StructuredRateTest < ActiveSupport::TestCase
  include StructuredLoanTestHelper

  setup do
    @family = families(:dylan_family)
    ReferenceRate.delete_all
  end

  test "daily accrual reproduces the lender's balance to the cent" do
    result = Loan::Simulator.new(
      starting_balance: 157_500,
      accrual_start_date: MORTGAGE_START,
      payment_schedule: (1..360).map { |number| MORTGAGE_START >> number },
      accrual_rate_for: ->(_date) { BigDecimal("1.5") },
      currency_precision: 2,
      day_count: :actual_365
    ).run
    payments = result.payments

    assert_equal BigDecimal("543.56"), payments.first[:payment_amount]
    # 31 days of December-January: 157,500 x 1.5 x 31 / 36,500.
    assert_equal BigDecimal("200.65"), payments.first[:interest_payment]
    # February is three days shorter and costs less on almost the same balance.
    assert_operator payments.third[:interest_payment], :<, payments.second[:interest_payment] - 15
    # The outstanding debt the lender quoted after the November 2026 instalment.
    assert_equal BigDecimal("153665.10"), payments[10][:ending_balance]
    assert_equal BigDecimal("2144.26"), payments.first(11).sum { |row| row[:interest_payment] }
  end

  test "monthly accrual is unchanged by default" do
    result = Loan::Simulator.new(
      starting_balance: 157_500,
      accrual_start_date: MORTGAGE_START,
      payment_schedule: (1..360).map { |number| MORTGAGE_START >> number },
      accrual_rate_for: ->(_date) { BigDecimal("1.5") },
      currency_precision: 2
    ).run

    assert_equal BigDecimal("196.88"), result.payments.first[:interest_payment]
    assert_equal BigDecimal("153662.55"), result.payments[10][:ending_balance]
  end

  test "daily interest across a year end divides each day by its own year" do
    interest = Loan::Simulator.daily_interest(
      balance: BigDecimal("100000"), from: Date.new(2027, 12, 12), to: Date.new(2028, 1, 12),
      rate_for: ->(_date) { BigDecimal("3.65") }, currency_precision: 2
    )

    expected = (BigDecimal("100000") * BigDecimal("3.65") / 100 * (BigDecimal("20") / 365 + BigDecimal("11") / 366)).round(2)
    assert_equal expected, interest
  end

  test "the opening period applies its bonuses to the fixed rate" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)
      revision = loan.rate_reviewer.revision_on(Date.new(2026, 6, 1))

      assert_equal BigDecimal("1.5"), revision.rate
      assert_equal BigDecimal("1.2"), revision.bonus_points
      assert_equal BigDecimal("1.5"), loan.current_variable_rate
    end
  end

  test "the next revision is projected from the latest published index until its own month is out" do
    store_euribor(Date.new(2026, 9, 1) => BigDecimal("3.247"), Date.new(2026, 10, 1) => BigDecimal("3.2385909"))

    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)
      upcoming = loan.rate_reviewer.next_revision

      assert_equal Date.new(2026, 12, 12), upcoming.effective_on
      assert upcoming.new_record?
      # October's average, published to three decimals, + 1.80 - 1.20.
      assert_equal BigDecimal("3.239"), upcoming.index_value
      assert_equal Date.new(2026, 10, 1), upcoming.index_month, "labelled with the month the value comes from"
      assert_equal BigDecimal("3.839"), upcoming.rate
    end
  end

  test "the schedule keeps the instalment on the revision date and resizes the next one" do
    store_euribor(Date.new(2026, 10, 1) => BigDecimal("3.2385909"))

    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)
      payments = loan.amortization_schedule.payments

      assert_equal BigDecimal("543.56"), payments[11].payment.amount
      assert_equal Date.new(2026, 12, 12), payments[11].date
      assert_equal BigDecimal("153310.99"), payments[11].ending_balance.amount
      # 153,310.99 over the 348 payments left at 3.839% / 12.
      assert_equal BigDecimal("731.01"), payments[12].payment.amount
      assert loan.amortization_schedule.re_amortising?
      assert_equal BigDecimal("731.01"), loan.payment_due_on(Date.new(2027, 1, 12)).amount
    end
  end

  test "a revision is recorded once the month before it is published, and then stays put" do
    store_euribor(Date.new(2026, 10, 1) => BigDecimal("3.2385909"))

    travel_to Date.new(2026, 12, 12) do
      loan = build_structured_mortgage(family: @family)
      loan.rate_reviewer.record_due!

      assert_equal [ MORTGAGE_START ], loan.rate_revisions.reload.map(&:effective_on),
        "December's revision waits for November's index"

      store_euribor(Date.new(2026, 11, 1) => BigDecimal("3.3"))
      created = loan.rate_reviewer.record_due!

      assert_equal [ Date.new(2026, 12, 12) ], created.map(&:effective_on)
      assert_equal BigDecimal("3.9"), created.first.rate
      assert_equal Date.new(2026, 11, 1), created.first.index_month

      # Dropping a bonus moves only what has not been recorded yet.
      loan.rate_bonuses.find_by!(kind: "payroll").update!(active: false)
      loan.reload

      assert_equal BigDecimal("3.9"), loan.rate_reviewer.revision_on(Date.new(2027, 6, 1)).rate
      assert_equal BigDecimal("4.2"), loan.rate_reviewer.revision_on(Date.new(2028, 1, 1)).rate
      assert_equal BigDecimal("1.5"), loan.rate_reviewer.revision_on(Date.new(2026, 6, 1)).rate
    end
  end

  test "a revision whose index never arrives falls back to the latest value after the grace period" do
    store_euribor(Date.new(2026, 10, 1) => BigDecimal("3.2385909"))

    travel_to Date.new(2026, 12, 12) + Loan::RateReviewer::INDEX_GRACE_DAYS do
      loan = build_structured_mortgage(family: @family)
      created = loan.rate_reviewer.record_due!

      december = created.find { |revision| revision.effective_on == Date.new(2026, 12, 12) }
      assert_equal Date.new(2026, 10, 1), december.index_month
      assert_equal BigDecimal("3.839"), december.rate
    end
  end

  test "the floor stops a negative index from producing a negative rate" do
    store_euribor(Date.new(2026, 11, 1) => BigDecimal("-2.5"))

    travel_to Date.new(2026, 12, 13) do
      loan = build_structured_mortgage(family: @family)
      loan.rate_reviewer.record_due!

      assert_equal BigDecimal("0"), loan.rate_revisions.find_by!(effective_on: Date.new(2026, 12, 12)).rate
    end
  end

  test "a later fixed period replaces the variable rate from its start" do
    store_euribor(Date.new(2026, 10, 1) => BigDecimal("3.2385909"))

    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)
      loan.rate_periods.create!(starts_on: Date.new(2027, 12, 12), rate_kind: "fixed", base_rate: 3.5,
                                review_interval_months: 12, lender_name: "Otro banco")
      loan.reload

      assert_equal BigDecimal("3.839"), loan.rate_reviewer.revision_on(Date.new(2027, 6, 1)).rate
      assert_equal BigDecimal("2.3"), loan.rate_reviewer.revision_on(Date.new(2028, 6, 1)).rate
      assert_equal BigDecimal("2.3"), loan.rate_reviewer.revision_on(Date.new(2040, 6, 1)).rate
    end
  end

  test "a structured loan needs no rate column" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)
      loan.update!(interest_rate: nil)

      assert_equal BigDecimal("543.56"), loan.reload.amortization_schedule.payments.first.payment.amount
    end
  end

  test "a yearly transfer into the loan is not mistaken for the instalment" do
    store_euribor(Date.new(2026, 10, 1) => BigDecimal("3.2385909"), Date.new(2026, 11, 1) => BigDecimal("3.3"))

    travel_to Date.new(2026, 12, 13) do
      loan = build_structured_mortgage(family: @family)
      source = @family.accounts.create!(name: "Ahorro", balance: 10_000, currency: "EUR", accountable: Depository.new)
      yearly = ScheduledPayment.create!(
        family: @family, account: source, target_account: loan.account, payment_type: "transfer",
        title: "Amortización anual", amount: 3000, currency: "EUR", frequency: "yearly",
        start_date: Date.new(2027, 1, 12), next_run_date: Date.new(2027, 1, 12)
      )

      loan.rate_reviewer.record_due!
      loan.reload.sync_scheduled_payments!

      assert_equal BigDecimal("3000"), yearly.reload.amount
    end
  end

  test "a loan without rate periods keeps reading its own columns" do
    loan = loans(:one)

    assert_not loan.structured_rate?
    assert_equal BigDecimal("3.5"), Loan::RateResolver.for(loan).accrual_rate_for(Date.current)
  end

  test "bonuses report what they save against what they cost" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)
      life = loan.rate_bonuses.find_by!(kind: "life_insurance")
      home = loan.rate_bonuses.find_by!(kind: "home_insurance")

      assert_equal BigDecimal("921.99"), life.annual_saving_on(BigDecimal("153665.10")).amount
      assert_equal BigDecimal("745.86"), life.annual_net_on(BigDecimal("153665.10")).amount
      assert home.annual_net_on(BigDecimal("153665.10")).negative?
    end
  end

  test "the Agenda instalment follows a recorded revision without touching the one due that day" do
    store_euribor(Date.new(2026, 10, 1) => BigDecimal("3.2385909"), Date.new(2026, 11, 1) => BigDecimal("3.3"))

    travel_to Date.new(2026, 12, 13) do
      loan = build_structured_mortgage(family: @family)
      source = @family.accounts.create!(name: "Cuenta hipoteca", balance: 1000, currency: "EUR", accountable: Depository.new)
      scheduled = ScheduledPayment.create!(
        family: @family, account: source, target_account: loan.account, payment_type: "transfer",
        title: "Cuota hipoteca", amount: 543.56, currency: "EUR", frequency: "monthly",
        start_date: Date.new(2026, 1, 12), next_run_date: Date.new(2027, 1, 12)
      )
      # December's occurrence was generated at 543.56; the series now waits on January.
      scheduled.update_columns(next_run_date: Date.new(2027, 1, 12))

      loan.rate_reviewer.record_due!
      loan.reload.sync_scheduled_payments!

      # 153,310.99 over 348 payments at 3.90% / 12.
      expected = Loan::AmortizationMath.level_payment(
        balance: BigDecimal("153310.99"), monthly_rate: BigDecimal("3.9") / 100 / 12,
        remaining_payments: 348, currency_precision: 2
      )
      assert_equal expected, scheduled.reload.amount
    end
  end
end
