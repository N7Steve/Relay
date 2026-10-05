require "test_helper"

class InactiveFamilyCleanerJobTest < ActiveJob::TestCase
  test "already queued commercial cleanup never archives or destroys families" do
    family = families(:inactive_trial)
    before = family.attributes
    Provider::Registry.expects(:get_provider).with(:stripe).never

    ClimateControl.modify(SELF_HOSTED: "false", SELF_HOSTING_ENABLED: "false") do
      assert_no_difference [ "Family.count", "User.count", "Account.count" ] do
        InactiveFamilyCleanerJob.perform_now
        InactiveFamilyCleanerJob.perform_now(dry_run: true)
      end
    end

    assert_equal before, family.reload.attributes
  end
end
