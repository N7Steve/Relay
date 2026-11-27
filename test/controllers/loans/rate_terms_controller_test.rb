require "test_helper"

class Loans::RateTermsControllerTest < ActionDispatch::IntegrationTest
  include StructuredLoanTestHelper
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @family = families(:dylan_family)
    ReferenceRate.delete_all
  end

  test "adding a period records the revisions already due and shows them on the rates tab" do
    travel_to Date.new(2026, 11, 27) do
      account = accounts(:loan)
      account.loan.update!(start_date: MORTGAGE_START, term_months: 360, initial_balance: 157_500)

      assert_difference -> { account.loan.rate_revisions.count }, 1 do
        post loan_rate_periods_path(account), params: {
          loan_rate_period: { starts_on: MORTGAGE_START, rate_kind: "fixed", base_rate: "1.5", review_interval_months: 12 }
        }
      end
      assert_redirected_to account_path(account, tab: "rates")

      get account_path(account, tab: "rates")
      assert_response :success
      assert_match "1.5%", response.body
    end
  end

  test "an invalid period re-renders the form" do
    post loan_rate_periods_path(accounts(:loan)), params: {
      loan_rate_period: { starts_on: "", rate_kind: "variable", review_interval_months: 12 }
    }

    assert_response :unprocessable_entity
  end

  test "bonuses can be added and switched off" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family, bonuses: false)

      post loan_rate_bonuses_path(loan.account), params: {
        loan_rate_bonus: { name: "Seguro de vida", kind: "life_insurance", points: "0.6", annual_cost: "176.13", active: "1" }
      }
      bonus = loan.rate_bonuses.reload.sole
      assert bonus.active?

      patch loan_rate_bonus_path(loan.account, bonus), params: { loan_rate_bonus: { active: "0" } }
      assert_not bonus.reload.active?
    end
  end

  test "confirming a revision freezes the figures from the lender's notice" do
    store_euribor(Date.new(2026, 11, 1) => BigDecimal("3.3"))

    travel_to Date.new(2026, 12, 13) do
      loan = build_structured_mortgage(family: @family)
      loan.rate_reviewer.record_due!
      revision = loan.rate_revisions.find_by!(effective_on: Date.new(2026, 12, 12))

      patch loan_rate_revision_path(loan.account, revision), params: { loan_rate_revision: { rate: "3.899" } }

      assert_redirected_to account_path(loan.account, tab: "rates")
      assert revision.reload.confirmed?
      assert_equal BigDecimal("3.899"), revision.rate
    end
  end

  test "index values typed by hand need a super admin" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)

      post loan_reference_rates_path(loan.account), params: {
        reference_rate: { index_key: "euribor_12m", month: "2026-08", value: "3.0" }
      }
      assert_nil ReferenceRate.find_by(month: Date.new(2026, 8, 1)), "a family admin administers one family, not the instance"

      @user.update!(role: "super_admin")

      post loan_reference_rates_path(loan.account), params: {
        reference_rate: { index_key: "euribor_12m", month: "2026-10", value: "3.239" }
      }

      assert_redirected_to account_path(loan.account, tab: "rates")
      assert_equal BigDecimal("3.239"), ReferenceRate.find_by!(month: Date.new(2026, 10, 1)).value

      sign_in users(:family_member)
      post loan_reference_rates_path(loan.account), params: {
        reference_rate: { index_key: "euribor_12m", month: "2026-09", value: "3.1" }
      }
      assert_nil ReferenceRate.find_by(month: Date.new(2026, 9, 1))
    end
  end

  test "the scenarios tab compares a switch to fixed" do
    store_euribor(Date.new(2026, 10, 1) => BigDecimal("3.2385909"))

    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)

      get loan_scenario_path(loan.account)
      assert_response :success
      assert_select "turbo-frame#loan_scenarios"

      get loan_scenario_path(loan.account), params: {
        scenario: { change_kind: "fixed", change_on: "2026-12-12", change_rate: "2.5", change_cost: "500", index_shift: "0" }
      }
      assert_response :success
      assert_match "731", response.body
    end
  end

  test "a prepayment is recorded with its transfer" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)
      source = @family.accounts.create!(name: "Cuenta hipoteca", owner: @user, balance: 30_000, currency: "EUR", accountable: Depository.new)

      assert_difference -> { loan.prepayments.count }, 1 do
        post loan_prepayments_path(loan.account), params: {
          loan_prepayment: { paid_on: "2026-11-20", amount: "10000", mode: "reduce_term", fee: "0", source_account_id: source.id }
        }
      end
      assert_redirected_to account_path(loan.account, tab: "rates")
      assert loan.prepayments.sole.entry.present?

      get account_path(loan.account, tab: "rates")
      assert_response :success
    end
  end

  test "correcting a period records its revisions again" do
    store_euribor(Date.new(2026, 11, 1) => BigDecimal("3.3"))

    travel_to Date.new(2026, 12, 13) do
      loan = build_structured_mortgage(family: @family)
      loan.rate_reviewer.record_due!
      variable = loan.rate_periods.find_by!(rate_kind: "variable")

      patch loan_rate_period_path(loan.account, variable), params: { loan_rate_period: { spread: "1.5" } }

      assert_equal BigDecimal("3.6"), loan.rate_revisions.reload.find_by!(effective_on: Date.new(2026, 12, 12)).rate
    end
  end

  test "a period saved before its bonuses is put right by recalculating" do
    travel_to Date.new(2026, 11, 27) do
      account = accounts(:loan)
      account.loan.update!(start_date: MORTGAGE_START, term_months: 360, initial_balance: 157_500)
      post loan_rate_periods_path(account), params: {
        loan_rate_period: { starts_on: MORTGAGE_START, rate_kind: "fixed", base_rate: "2.7", review_interval_months: 12 }
      }
      account.loan.rate_bonuses.create!(name: "Seguro de vida", kind: "life_insurance", points: 1.2)
      assert_equal BigDecimal("2.7"), account.loan.rate_revisions.reload.sole.rate, "recorded before the bonus existed"

      post loan_rate_review_path(account, recalculate: 1)

      assert_redirected_to account_path(account, tab: "rates")
      assert_equal BigDecimal("1.5"), account.loan.rate_revisions.reload.sole.rate
    end
  end

  test "a managed loan's account refuses movements from ordinary screens" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family, interest_tracking: true)
      create_valuation(account: loan.account, date: MORTGAGE_START, amount: 157_500, currency: "EUR", kind: "opening_anchor")
      source = @family.accounts.create!(name: "Cuenta hipoteca", owner: @user, balance: 5_000, currency: "EUR", accountable: Depository.new)

      assert_no_difference -> { loan.account.entries.count } do
        post transfers_path, params: { transfer: { from_account_id: source.id, to_account_id: loan.account.id, date: "2026-11-20", amount: "543.56" } }
      end
      assert_equal I18n.t("loans.contract.closed"), flash[:alert]

      Loan::InterestLedger.new(loan.reload).refresh!
      interest = loan.account.entries.find_by!(source: Loan::InterestLedger::SOURCE, date: Date.new(2026, 1, 12))
      patch transaction_path(interest), params: { entry: { amount: "1" } }
      assert_equal BigDecimal("200.65"), interest.reload.amount

      delete transaction_path(interest)
      assert interest.reload.persisted?

      get transaction_path(interest)
      assert_response :success
      assert_match(/157[.,]500/, response.body, "the average principal of the period")
    end
  end

  test "the loan adopts an existing Agenda series and Agenda can no longer change it" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family, interest_tracking: false)
      source = @family.accounts.create!(name: "Cuenta hipoteca", owner: @user, balance: 5_000, currency: "EUR", accountable: Depository.new)
      series = ScheduledPayment.create!(
        family: @family, account: source, target_account: loan.account, payment_type: "transfer",
        title: "Cuota Hipoteca", amount: 543.56, currency: "EUR", frequency: "monthly",
        start_date: Date.new(2026, 1, 12), next_run_date: Date.new(2026, 12, 12)
      )
      series.update_columns(next_run_date: Date.new(2026, 12, 12))
      loan.update!(interest_tracking: true)

      post loan_instalment_series_path(loan.account, scheduled_payment_id: series.id)
      assert_redirected_to account_path(loan.account, tab: "rates")
      assert_equal loan, series.reload.loan

      delete scheduled_payment_path(series)
      assert ScheduledPayment.exists?(series.id)

      patch scheduled_payment_path(series), params: { scheduled_payment: { amount: "1", title: "Cuota" } }
      assert_equal "Cuota Hipoteca", series.reload.title, "a payment order of the contract is not edited from Agenda"
      assert_equal BigDecimal("543.56"), series.amount
      assert_equal I18n.t("scheduled_payments.loan_managed"), flash[:alert]

      post toggle_status_scheduled_payment_path(series)
      assert series.reload.active?, "nor paused"

      get edit_scheduled_payment_path(series)
      assert_response :success
      assert_select "dialog input[name^='scheduled_payment']", count: 0, message: "the dialog shows the series without its form"
      assert_select "a[href='#{account_path(loan.account, tab: "overview")}']", count: 1

      get confirm_entry_form_scheduled_payment_path(series, scheduled_date: "2026-12-12")
      assert_response :success
      assert_select "input[name='confirm_amount']", count: 0, message: "the instalment is the contract's, not typed"
      assert_select "input[name='confirm_date']", count: 1
    end
  end

  test "another family's loan is out of reach" do
    other = accounts(:loan)
    other.update_columns(family_id: families(:empty).id)

    post loan_rate_periods_path(other), params: { loan_rate_period: { starts_on: Date.current, rate_kind: "fixed", base_rate: "2" } }

    assert_response :not_found
  end
end
