# frozen_string_literal: true

require "test_helper"

class Api::V1::LoansControllerTest < ActionDispatch::IntegrationTest
  include StructuredLoanTestHelper

  setup do
    @user = users(:family_admin)
    @family = families(:dylan_family)
    ReferenceRate.delete_all

    @user.api_keys.active.destroy_all
    @api_key = ApiKey.create!(
      user: @user,
      name: "Test Read Key",
      scopes: [ "read" ],
      source: "web",
      display_key: "test_read_#{SecureRandom.hex(8)}"
    )
  end

  test "requires authentication" do
    get "/api/v1/loans"

    assert_response :unauthorized
    assert_equal "unauthorized", JSON.parse(response.body)["error"]
  end

  test "requires the read scope" do
    key = ApiKey.new(user: @user, name: "No Read Key", scopes: [], source: "web", display_key: "no_read_#{SecureRandom.hex(8)}")
    # Valid persisted API keys can only be read/read_write; this bypasses
    # validations to exercise the runtime insufficient-scope guard.
    key.save!(validate: false)

    get "/api/v1/loans", headers: api_headers(key)

    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]
  end

  test "lists only the loans the user can read, with their headline figures" do
    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family)

      get "/api/v1/loans", headers: api_headers(@api_key)

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "2026-11-27", body["as_of"]

      account_ids = body["loans"].map { |row| row.dig("account", "id") }
      assert_includes account_ids, loan.account.id
      assert_includes account_ids, accounts(:loan).id
      assert_not_includes account_ids, accounts(:depository).id
      assert body["loans"].all? { |row| row.dig("account", "account_type") == "loan" }

      row = body["loans"].find { |item| item.dig("account", "id") == loan.account.id }
      assert_equal "mortgage", row.dig("account", "subtype")
      summary = row["summary"]
      assert_equal "EUR", summary["currency"]
      assert_equal "157500.0", summary.dig("original_principal", "amount")
      assert_equal "1.5", summary["current_rate"]
      assert_equal "543.56", summary.dig("payment", "amount")
      assert_equal "2026-12-12", summary["next_payment_date"]
      assert_equal 12, summary["next_payment_number"]
      assert_equal 360, summary["term_months"]
      assert_equal "2055-12-12", summary["payoff_date"]
      assert summary["structured_rate"]
      assert_nil summary["principal_repaid"], "only a loan that posts its interest knows the split"
    end
  end

  test "shows the Bankinter mortgage: debt, instalment, rate revisions and schedule" do
    store_euribor(Date.new(2026, 9, 1) => BigDecimal("3.247"), Date.new(2026, 10, 1) => BigDecimal("3.2385909"))

    travel_to Date.new(2026, 11, 27) do
      loan = build_structured_mortgage(family: @family, interest_tracking: true)
      loan.rate_reviewer.record_due!
      # The lender's figures after eleven instalments: 3,834.90 of principal
      # and 2,144.26 of interest repaid.
      Loan::ContractWrites.allow do
        loan.account.entries.create!(
          date: Date.new(2026, 11, 12), amount: BigDecimal("2144.26"), currency: "EUR", name: "Intereses",
          source: Loan::InterestLedger::SOURCE, external_id: "2026-11-12",
          entryable: Transaction.new(kind: Loan::InterestLedger::KIND)
        )
      end
      loan.account.update_columns(balance: BigDecimal("153665.10"))

      get "/api/v1/loans/#{loan.account.id}", headers: api_headers(@api_key)

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal loan.account.id, body.dig("account", "id")

      summary = body["summary"]
      assert_equal "153665.1", summary.dig("current_debt", "amount")
      assert_equal "3834.9", summary.dig("principal_repaid", "amount")
      assert_equal "2144.26", summary.dig("interest_paid", "amount")
      assert_in_delta 0.0243, summary["repaid_ratio"], 0.0001
      assert summary["interest_tracking"]

      instalment = body["current_instalment"]
      assert_equal 12, instalment["number"]
      assert_equal "2026-12-12", instalment["date"]
      assert_equal "543.56", instalment.dig("total", "amount")
      assert_equal BigDecimal("543.56"),
                   BigDecimal(instalment.dig("principal", "amount")) + BigDecimal(instalment.dig("interest", "amount"))
      assert_in_delta 1.0, instalment.dig("ratios", "principal") + instalment.dig("ratios", "interest"), 0.001

      rate = body["rate"]
      assert rate["structured"]
      assert_equal "1.5", rate["current_rate"]
      assert_equal "1.5", rate.dig("current", "rate")
      assert_equal "fixed", rate.dig("current", "rate_kind")
      assert_equal "2.7", rate.dig("current", "base_rate")
      assert_equal "1.2", rate.dig("current", "bonus_points")
      assert_equal "calculated", rate.dig("current", "status")

      upcoming = rate["next_revision"]
      assert_equal "2026-12-12", upcoming["effective_on"]
      assert_equal "projected", upcoming["status"]
      assert_equal "variable", upcoming["rate_kind"]
      assert_equal "euribor_12m", upcoming["reference_index"]
      assert_equal "2026-10-01", upcoming["index_month"]
      assert_equal "3.239", upcoming["index_value"]
      assert_equal "1.8", upcoming["spread"]
      assert_equal "3.839", upcoming["rate"]
      assert upcoming["composition"].present?
      # The revision on a payment date resizes the instalment after it.
      assert_equal "2027-01-12", upcoming["new_payment_date"]
      assert_operator BigDecimal(upcoming.dig("new_payment", "amount")), :>, BigDecimal("543.56")

      assert_equal [ "2025-12-12", "2026-12-12" ], rate["revisions"].map { |revision| revision["effective_on"] }
      assert_equal %w[fixed variable], rate["periods"].map { |period| period["rate_kind"] }
      assert_equal 3, rate["bonuses"].size
      assert rate["bonuses"].all? { |bonus| bonus["active"] }
      assert_equal "0.6", rate["bonuses"].first["points"]

      schedule = body["schedule"]
      assert_equal "EUR", schedule["currency"]
      assert_equal 360, schedule["payments"].size
      assert_equal 11, schedule["payments"].count { |payment| payment["past"] }
      assert_equal "153665.1", schedule["payments"][10]["ending_balance"]
      assert_equal "2055-12-12", schedule["payoff_date"]
    end
  end

  test "a loan without structured rates answers with its column rate and no revisions" do
    travel_to Date.new(2026, 11, 27) do
      get "/api/v1/loans/#{accounts(:loan).id}", headers: api_headers(@api_key)

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "3.5", body.dig("rate", "current_rate")
      assert_not body.dig("rate", "structured")
      assert_nil body.dig("rate", "current")
      assert_nil body.dig("rate", "next_revision")
      assert_equal [], body.dig("rate", "revisions")
      assert_equal [], body.dig("rate", "periods")
      assert_equal [], body.dig("rate", "bonuses")
      assert_equal 360, body.dig("schedule", "payments").size
    end
  end

  test "a loan that cannot be amortised has no schedule or instalment" do
    accounts(:loan).loan.update!(term_months: nil)

    get "/api/v1/loans/#{accounts(:loan).id}", headers: api_headers(@api_key)

    assert_response :success
    body = JSON.parse(response.body)
    assert_nil body["schedule"]
    assert_nil body["current_instalment"]
    assert_nil body.dig("summary", "payment")
    assert_nil body.dig("summary", "payoff_date")
  end

  test "an account that is not a loan is not found" do
    get "/api/v1/loans/#{accounts(:depository).id}", headers: api_headers(@api_key)

    assert_response :not_found
    assert_equal "record_not_found", JSON.parse(response.body)["error"]
  end

  test "a malformed id is not found" do
    get "/api/v1/loans/not-a-uuid", headers: api_headers(@api_key)

    assert_response :not_found
  end

  test "another family's loan is not found" do
    other_user = users(:family_member)
    other_user.update!(family: families(:empty))
    other_user.api_keys.active.destroy_all
    other_key = ApiKey.create!(
      user: other_user,
      name: "Other Family Read Key",
      scopes: [ "read" ],
      source: "web",
      display_key: "other_family_read_#{SecureRandom.hex(8)}"
    )

    get "/api/v1/loans/#{accounts(:loan).id}", headers: api_headers(other_key)
    assert_response :not_found

    get "/api/v1/loans", headers: api_headers(other_key)
    assert_response :success
    assert_not_includes JSON.parse(response.body)["loans"].map { |row| row.dig("account", "id") }, accounts(:loan).id
  end
end
