require "test_helper"

class GoogleDriveOauthConfigurationTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
  end

  test "changing credentials requires reconnecting an existing Drive connection" do
    connection = GoogleDriveConnection.create!(
      family: @user.family,
      user: @user,
      google_subject: "oauth-configuration-test",
      email: "drive@example.com",
      refresh_token: "refresh-token",
      connected_at: Time.current
    )
    schedule = GoogleDriveExportSchedule.create!(
      family: @user.family,
      user: @user,
      google_drive_connection: connection,
      name: "Daily export",
      filename: "transactions.csv",
      frequency: :daily,
      run_at: "06:00",
      timezone: "UTC",
      date_range: :all_history,
      filters: { account_ids: [ @user.accessible_accounts.first.id ] },
      next_run_at: 1.day.from_now
    )

    GoogleDriveOauthConfiguration.create!(
      family: @user.family,
      user: @user,
      client_id: "new-client-id",
      client_secret: "new-client-secret"
    )

    assert connection.reload.requires_reauthorization?
    assert schedule.reload.needs_attention?
    assert_equal "reauthorization_required", schedule.last_error_code
  end

  test "rejects a user from another family" do
    configuration = GoogleDriveOauthConfiguration.new(
      family: families(:empty),
      user: @user,
      client_id: "client-id",
      client_secret: "client-secret"
    )

    assert_not configuration.valid?
    assert configuration.errors.of_kind?(:user, :invalid)
  end
end
