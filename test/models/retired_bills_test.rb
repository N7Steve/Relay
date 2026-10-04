require "test_helper"

class RetiredBillsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "historical series saves do not materialize occurrences or Agenda payments" do
    series = recurring_transactions(:netflix_subscription)
    assert_no_difference [ "RecurringOccurrence.count", "ScheduledPayment.count", "ScheduledPaymentEntry.count" ] do
      assert_no_enqueued_jobs do
        series.update!(expected_day_of_month: 20, amount: series.amount + 1)
        copy = series.dup
        copy.amount += 1
        copy.save!
      end
    end
  end

  test "old serialized Bills jobs finish without generating data or enqueueing work" do
    jobs = [
      IdentifyRecurringTransactionsJob.new(families(:dylan_family).id, Time.current.to_f),
      GenerateRecurringOccurrencesJob.new,
      GenerateRecurringOccurrencesJob.new(families(:dylan_family).id)
    ]
    assert_no_difference [ "RecurringTransaction.count", "RecurringOccurrence.count", "RecurringAllocation.count", "ScheduledPayment.count" ] do
      assert_no_enqueued_jobs do
        jobs.each { |job| ActiveJob::Base.execute(job.serialize) }
      end
    end
  end

  test "local sync completion does not schedule Bills identification" do
    family = families(:dylan_family)
    family.stubs(:broadcast_replace_to)

    assert_no_enqueued_jobs only: IdentifyRecurringTransactionsJob do
      Family::SyncCompleteEvent.new(family).broadcast
    end
  end

  test "insights generation excludes Bills and retains budget and goal generators" do
    result = Insight::GeneratorRegistry.new(families(:dylan_family)).generate_all
    assert_empty result.succeeded_types & Insight::BILLS_BACKED_TYPES
    assert_includes result.succeeded_types, "budget_at_risk"
    assert_includes result.succeeded_types, "maintained_goal_depleted"
  end
end
