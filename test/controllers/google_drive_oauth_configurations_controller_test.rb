require "test_helper"

class GoogleDriveOauthConfigurationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    sign_in @user
  end

  test "stores OAuth credentials for the current user" do
    assert_difference "GoogleDriveOauthConfiguration.count", 1 do
      patch google_drive_oauth_configuration_path, params: {
        google_drive_oauth_configuration: {
          client_id: "personal-client-id",
          client_secret: "personal-client-secret"
        }
      }
    end

    assert_redirected_to family_exports_path
    configuration = @user.reload.google_drive_oauth_configuration
    assert_equal "personal-client-id", configuration.client_id
    assert_equal "personal-client-secret", configuration.client_secret
  end

  test "keeps the stored secret when the field is blank" do
    configuration = GoogleDriveOauthConfiguration.create!(
      family: @user.family,
      user: @user,
      client_id: "old-client-id",
      client_secret: "stored-secret"
    )

    patch google_drive_oauth_configuration_path, params: {
      google_drive_oauth_configuration: {
        client_id: "new-client-id",
        client_secret: ""
      }
    }

    assert_redirected_to family_exports_path
    assert_equal "new-client-id", configuration.reload.client_id
    assert_equal "stored-secret", configuration.client_secret
  end

  test "does not update another user's OAuth configuration" do
    other_user = users(:family_member)
    other_configuration = GoogleDriveOauthConfiguration.create!(
      family: other_user.family,
      user: other_user,
      client_id: "other-client-id",
      client_secret: "other-client-secret"
    )

    patch google_drive_oauth_configuration_path, params: {
      google_drive_oauth_configuration: {
        client_id: "current-user-client-id",
        client_secret: "current-user-client-secret"
      }
    }

    assert_equal "other-client-id", other_configuration.reload.client_id
  end
end
