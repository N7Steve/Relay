require "application_system_test_case"

class McpPendingChangesSystemTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
    key = ApiKey.create!(user: @user, name: "Assistant proposals", scopes: %w[read_write], source: "web", display_key: SecureRandom.hex(32))
    access = Api::Access.new(user: @user, scopes: key.scopes, credential: key)
    receipt = Mcp::ChangeSet.stage!(access: access, name: "update_profile", arguments: { first_name: "Proposed name", idempotency_key: "system-proposal" })
    @change_set = Mcp::ChangeSet.find(receipt[:change_set_id])
    login_as @user
  end

  test "settings shows a grouped proposal and discarding preserves canonical data" do
    original_name = @user.first_name
    visit settings_pending_changes_path
    assert_text I18n.t("settings.pending_changes.title")
    assert_text "Assistant proposals"
    click_link href: settings_pending_change_path(@change_set)
    assert_text I18n.t("settings.pending_changes.domains.settings")
    assert_text I18n.t("settings.pending_changes.actions.update")
    assert_button I18n.t("settings.pending_changes.show.approve")
    page.save_screenshot(Rails.root.join("tmp/screenshots/mcp-pending-changes.png"))
    click_on I18n.t("settings.pending_changes.show.reject")
    assert_text I18n.t("settings.pending_changes.statuses.rejected")
    assert_equal "rejected", @change_set.reload.status
    assert_equal original_name, @user.reload.first_name
  end

  test "approval requires the visible confirmation and queues the reviewed proposal" do
    visit settings_pending_change_path(@change_set)
    click_on I18n.t("settings.pending_changes.show.approve")
    within "#confirm-dialog" do
      assert_text I18n.t("settings.pending_changes.show.confirm")
      click_button I18n.t("layouts.shared.confirm_dialog.confirm"), visible: true
    end
    assert_text I18n.t("settings.pending_changes.statuses.approved")
    assert_equal "approved", @change_set.reload.status
    assert_not_equal "Proposed name", @user.reload.first_name
  end
end
