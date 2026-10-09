require "test_helper"

class TransactionForecastBehaviorTest < ActiveSupport::TestCase
  test "legacy one time kind maps to exceptional once" do
    transaction = Transaction.create!(kind: "one_time")

    assert_predicate transaction, :forecast_exceptional_once?
    assert_predicate transaction, :standard?
  end

  test "irregular recurring is distinct from legacy one time" do
    transaction = Transaction.create!(forecast_behavior: "irregular_recurring")

    assert_predicate transaction, :forecast_irregular_recurring?
    assert_predicate transaction, :standard?
  end

  test "forecast behavior changes preserve the financial kind" do
    %w[standard funds_movement cc_payment loan_payment investment_contribution transfer_to_excluded transfer_from_excluded].each do |kind|
      transaction = Transaction.create!(kind: kind)
      transaction.update!(forecast_behavior: "exceptional_once")

      assert_equal kind, transaction.reload.kind
      assert_predicate transaction, :exceptional_for_forecast?
      assert_not Transaction.budget_reportable.exists?(transaction.id)

      transaction.update!(forecast_behavior: "normal")
      assert_equal kind, transaction.reload.kind
    end
  end

  test "legacy rows remain readable before normalization and explicit edits take precedence" do
    transaction = Transaction.create!
    transaction.update_columns(kind: "one_time", forecast_behavior: "normal")

    assert_predicate transaction.reload, :exceptional_for_forecast?
    assert_equal "exceptional_once", transaction.effective_forecast_behavior
    assert Transaction.exceptional_for_forecast.exists?(transaction.id)
    assert_not Transaction.budget_reportable.exists?(transaction.id)

    transaction.update!(forecast_behavior: "irregular_recurring")

    assert_predicate transaction.reload, :standard?
    assert_predicate transaction, :forecast_irregular_recurring?
    assert Transaction.budget_reportable.exists?(transaction.id)
  end

  test "normalizing a legacy record during an unrelated edit retains its exclusion" do
    transaction = Transaction.create!
    transaction.update_columns(kind: "one_time", forecast_behavior: "normal")

    transaction.reload.update!(investment_activity_label: "Fee")

    assert_predicate transaction.reload, :standard?
    assert_predicate transaction, :forecast_exceptional_once?
    assert_not Transaction.budget_reportable.exists?(transaction.id)
  end

  test "explicit normal wins over a legacy kind even when the stored behavior was already normal" do
    transaction = Transaction.create!
    transaction.update_columns(kind: "one_time", forecast_behavior: "normal")

    transaction.reload.update!(forecast_behavior: "normal")

    assert_predicate transaction.reload, :standard?
    assert_predicate transaction, :forecast_normal?
    assert Transaction.budget_reportable.exists?(transaction.id)
  end
end
