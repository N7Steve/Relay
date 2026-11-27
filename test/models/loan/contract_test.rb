require "test_helper"

# A loan that posts its interest is a closed contract: its account only takes
# the loan's own movements.
class Loan::ContractTest < ActiveSupport::TestCase
  include StructuredLoanTestHelper
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    ReferenceRate.delete_all
  end

  test "nothing is written to a managed loan's account by hand" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family, interest_tracking: true)

      error = assert_raises(ActiveRecord::RecordInvalid) do
        create_transaction(account: loan.account, date: Date.new(2026, 11, 20), amount: -543.56, currency: "EUR")
      end
      assert error.record.errors.added?(:base, :loan_contract_closed)

      assert_raises(ActiveRecord::RecordInvalid) do
        create_valuation(account: loan.account, date: Date.new(2026, 11, 20), amount: 150_000, currency: "EUR")
      end

      # The opening principal is the contract's starting point and stays writable.
      assert create_valuation(account: loan.account, date: MORTGAGE_START, amount: 157_500, currency: "EUR", kind: "opening_anchor").persisted?
    end
  end

  test "a loan that does not post interest stays open, as before" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family, interest_tracking: false)

      assert create_transaction(account: loan.account, date: Date.new(2026, 11, 20), amount: -543.56, currency: "EUR").persisted?
    end
  end

  test "the adopted Agenda series pays the schedule's instalment, whatever it says" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family, interest_tracking: true)
      source = @family.accounts.create!(name: "Cuenta hipoteca", balance: 5_000, currency: "EUR", accountable: Depository.new)
      series = ScheduledPayment.new(
        family: @family, account: source, target_account: loan.account, payment_type: "transfer",
        title: "Cuota hipoteca", amount: 999, currency: "EUR", frequency: "monthly",
        start_date: Date.new(2026, 12, 12), next_run_date: Date.new(2026, 12, 12)
      )
      assert_not series.valid?, "a managed loan takes no series it does not own"
      assert series.errors.added?(:target_account, :loan_contract_closed)

      loan.adopt_instalment_series!(scheduled_payment: series)
      assert_equal loan, series.reload.loan
      assert_equal BigDecimal("543.56"), series.amount, "synced to the schedule on adoption"
      assert_not loan.account.reload.enable_transfer_matcher

      occurrence = series.scheduled_payment_entries.create!(scheduled_date: Date.new(2026, 12, 12))
      occurrence.confirm!(amount_override: BigDecimal("1"))

      inflow = occurrence.reload.transfer_entry
      assert_equal loan.account, inflow.account
      assert_equal BigDecimal("-543.56"), inflow.amount
      assert inflow.loan_contract_locked?
    end
  end

  test "a new instalment series can be created from the loan" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family, interest_tracking: true)
      source = @family.accounts.create!(name: "Cuenta hipoteca", balance: 5_000, currency: "EUR", accountable: Depository.new)

      series = loan.adopt_instalment_series!(source_account: source)

      assert series.persisted?
      assert series.loan_managed?
      assert_equal Date.new(2026, 12, 12), series.next_run_date
      assert_equal "monthly", series.frequency
    end
  end

  test "a prepayment on a managed loan needs the paying account, and removing it removes its money" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family, interest_tracking: true)
      source = @family.accounts.create!(name: "Ahorro", balance: 30_000, currency: "EUR", accountable: Depository.new)

      without = Loan::PrepaymentRecorder.new(loan).record(paid_on: Date.new(2026, 11, 20), amount: 5_000, mode: "reduce_term")
      assert without.errors.added?(:source_account_id, :blank)

      prepayment = Loan::PrepaymentRecorder.new(loan, source_account: source)
        .record(paid_on: Date.new(2026, 11, 20), amount: 5_000, mode: "reduce_term")
      assert prepayment.persisted?
      assert prepayment.entry.loan_contract_locked?
      assert_not prepayment.entry.destroy, "only through the loan"

      Loan::PrepaymentRecorder.new(loan.reload).remove(prepayment)
      assert_equal 0, loan.account.entries.where(entryable_type: "Transaction").where.not(source: Loan::InterestLedger::SOURCE).count
      assert_equal 0, source.entries.count
    end
  end

  test "movements from before the loan was managed are listed and can be removed" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family, interest_tracking: false)
      create_valuation(account: loan.account, date: MORTGAGE_START, amount: 157_500, currency: "EUR", kind: "opening_anchor")
      stray = create_transaction(account: loan.account, date: Date.new(2026, 3, 1), amount: -100, currency: "EUR", name: "Ajuste")
      loan.update!(interest_tracking: true)

      assert_equal [ stray ], loan.reload.foreign_entries.to_a
      assert stray.reload.destroy, "a stray movement can be cleaned up"
    end
  end

  test "deleting the loan's account removes its contract with it" do
    travel_to Date.new(2026, 11, 27) do
      loan = mortgage_with_interest

      assert loan.account.destroy
      assert_equal 0, Entry.where(source: Loan::InterestLedger::SOURCE).count
    end
  end

  private
    def mortgage_with_interest
      loan = build_structured_mortgage(family: @family, interest_tracking: true)
      create_valuation(account: loan.account, date: MORTGAGE_START, amount: 157_500, currency: "EUR", kind: "opening_anchor")
      Loan::InterestLedger.new(loan.reload).refresh!
      loan
    end
end
