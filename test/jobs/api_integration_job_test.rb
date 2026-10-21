# frozen_string_literal: true

require "test_helper"

class ApiIntegrationJobTest < ActiveJob::TestCase
  setup do
    @user = users(:family_admin)
    @key = ApiKey.create!(user: @user, name: "Queued integration", scopes: %w[read_write], source: "web", display_key: "queued_#{SecureRandom.hex(12)}")
    @authority = Api::Access.new(user: @user, scopes: %w[read_write], credential: @key).delegated_authority
    @sync = accounts(:depository).syncs.create!
  end

  test "recalculation stays local when invoking the native sync job" do
    SyncJob.expects(:perform_now).with do |sync, options|
      assert ExternalAccess.local_recalculation?
      sync == @sync && options == { balances_only: true }
    end
    ApiIntegrationJob.perform_now("account", @sync, @authority)
  end

  test "revocation cancels pending work before reaching the native sync job" do
    @key.revoke!
    SyncJob.expects(:perform_now).never
    ApiIntegrationJob.perform_now("account", @sync, @authority)
    assert @sync.reload.stale?
  end

  test "a cancelled sync cannot start again from a delayed delivery" do
    @sync.request_cancel!
    SyncJob.expects(:perform_now).never
    ApiIntegrationJob.perform_now("account", @sync, @authority)
    assert @sync.reload.stale?
  end
end
