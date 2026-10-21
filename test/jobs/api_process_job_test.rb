# frozen_string_literal: true

require "test_helper"

class ApiProcessJobTest < ActiveJob::TestCase
  setup do
    @user = users(:family_admin)
    @key = ApiKey.create!(user: @user, name: "Jobs", scopes: %w[read_write], source: "web", display_key: "jobs_#{SecureRandom.hex(12)}")
    @export = @user.family.family_exports.create!(requested_by: @user)
    @authority = Api::Access.new(user: @user, scopes: %w[read_write], credential: @key).delegated_authority
  end

  test "delegated backup executes through the native job with current authority" do
    FamilyDataExportJob.expects(:perform_now).with(@export).once
    ApiProcessJob.perform_now("backup", @export, @authority)
  end

  test "revocation stops a queued export and records its failure" do
    @key.revoke!
    FamilyDataExportJob.expects(:perform_now).never
    assert_difference "DebugLogEntry.count", 1 do
      ApiProcessJob.perform_now("backup", @export, @authority)
    end
    assert @export.reload.failed?
  end

  test "loss of private account access or financial permission stops queued work" do
    accounts(:investment).update!(owner: users(:family_member))
    accounts(:investment).account_shares.where(user: @user).destroy_all
    FamilyDataExportJob.expects(:perform_now).never
    ApiProcessJob.perform_now("backup", @export, @authority)
    assert @export.reload.failed?
  end

  test "a downgraded key cannot execute an already queued import or revert" do
    row = @user.family.imports.create!(type: "TransactionImport", status: "reverting")
    @key.update!(scopes: %w[read])
    RevertImportJob.expects(:perform_now).never
    ApiProcessJob.perform_now("revert", row, @authority)
    assert row.reload.revert_failed?
    assert_match(/authority/, row.error)
  end

  test "revoked OAuth grants cannot execute a queued export" do
    client = Doorkeeper::Application.create!(name: "Queued client", redirect_uri: "https://client.example/callback", confidential: false, scopes: "read_write")
    token = Doorkeeper::AccessToken.create!(application: client, resource_owner_id: @user.id, scopes: "read_write", expires_in: 3600)
    authority = Api::Access.new(user: @user, scopes: %w[read_write], credential: token).delegated_authority
    token.revoke
    FamilyDataExportJob.expects(:perform_now).never
    ApiProcessJob.perform_now("backup", @export, authority)
    assert @export.reload.failed?
  end

  test "revocation preserves a committed import caught before its status write" do
    row = @user.family.imports.create!(type: "TransactionImport", status: "importing")
    row.entries << entries(:transaction)
    @key.revoke!
    ImportJob.expects(:perform_now).never
    ApiProcessJob.perform_now("publish", row, @authority)
    assert row.reload.complete?
    assert_equal 1, row.entries.count
  end
end
