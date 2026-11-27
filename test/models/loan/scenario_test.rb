require "test_helper"

class Loan::ScenarioTest < ActiveSupport::TestCase
  include StructuredLoanTestHelper

  setup do
    @family = families(:dylan_family)
    ReferenceRate.delete_all
    store_euribor(Date.new(2026, 10, 1) => BigDecimal("3.2385909"))
  end

  test "switching to a cheaper fixed rate saves interest, net of what the switch costs" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)
      scenario = Loan::Scenario.new(loan: loan, change_kind: "fixed", change_on: Date.new(2026, 12, 12),
                                    change_rate: 2.5, change_cost: 1_000)

      assert scenario.valid?
      assert_equal BigDecimal("731.01"), scenario.baseline.payment_after_change.amount
      assert_operator scenario.proposal.payment_after_change.amount, :<, BigDecimal("640")
      assert_operator scenario.net_saving, :>, 20_000
      assert_equal BigDecimal("1000"), scenario.proposal.costs
    end
  end

  test "the comparison is repeated under several index paths" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)
      scenario = Loan::Scenario.new(loan: loan, change_kind: "fixed", change_on: Date.new(2026, 12, 12), change_rate: 3.0)

      rows = scenario.sensitivity
      assert_equal [ -1, 0, 1, 2 ], rows.map { |row| row[:shift].to_i }
      # A fixed rate does not move with the index; the variable loan does.
      assert_equal 1, rows.map { |row| row[:proposal].remaining_interest }.uniq.size
      assert_operator rows.first[:baseline].remaining_interest, :<, rows.last[:baseline].remaining_interest
    end
  end

  test "a prepayment scenario shortens the loan" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)
      scenario = Loan::Scenario.new(loan: loan, prepayment_amount: 20_000, prepayment_on: Date.new(2026, 12, 12),
                                    prepayment_mode: "reduce_term")

      assert_operator scenario.months_saved, :>, 40
      assert_operator scenario.net_saving, :>, 0
    end
  end

  test "trying scenarios saves nothing and leaves the real schedule alone" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)
      before = loan.amortization_schedule.total_interest

      scenario = Loan::Scenario.new(loan: loan, change_kind: "fixed", change_on: Date.new(2026, 12, 12), change_rate: 1.0)
      scenario.proposal
      loan.rate_reviewer.timeline

      assert loan.rate_periods.all?(&:persisted?), "a hypothetical period must not join the loan's periods"
      assert loan.rate_revisions.all?(&:persisted?), "a projected revision must not join the loan's revisions"
      assert_equal 2, Loan::RatePeriod.where(loan_id: loan.id).count
      assert_equal before, loan.reload.amortization_schedule.total_interest
    end
  end

  test "a change of terms needs rate periods" do
    loan = loans(:one)
    loan.update!(start_date: Date.new(2020, 1, 1))
    scenario = Loan::Scenario.new(loan: loan, change_kind: "fixed", change_on: Date.current, change_rate: 2)

    assert_not scenario.valid?
    assert scenario.errors.added?(:change_kind, :requires_structured_rate)
  end
end
