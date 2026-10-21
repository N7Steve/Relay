require "application_system_test_case"

class McpPendingChangesSystemTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
    key = ApiKey.create!(user: @user, name: "Assistant proposals", scopes: %w[read_write], source: "web", display_key: SecureRandom.hex(32))
    @access = Api::Access.new(user: @user, scopes: key.scopes, credential: key)
    receipt = Mcp::ChangeSet.stage!(access: @access, name: "update_profile", arguments: { first_name: "Proposed name", idempotency_key: "system-proposal" })
    @change_set = Mcp::ChangeSet.find(receipt[:change_set_id])
    login_as @user
  end

  test "settings shows a grouped proposal and discarding preserves canonical data" do
    original_name = @user.first_name
    visit settings_pending_changes_path
    assert_text I18n.t("settings.pending_changes.title")
    assert_text "Assistant proposals"
    click_link href: settings_pending_change_path(@change_set)
    assert_text I18n.t("settings.pending_changes.types.settings", count: 1)
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

  test "review distinguishes expenses income transfers and categories in Spanish on desktop and mobile" do
    @user.update!(locale: "es", theme: "relay")
    source = accounts(:depository)
    source.update!(name: "Bankinter Nomina", currency: "EUR")
    destination = accounts(:connected)
    destination.update!(name: "Bankinter Hipoteca", currency: "EUR")
    [ source, destination ].each do |account|
      Mcp::ChangeSet.stage!(access: @access, name: "create_transaction", arguments: {
        account_id: account.id, name: "Test expense", amount: "1", date: Date.current.iso8601, idempotency_key: "expense-#{account.id}"
      })
    end
    Mcp::ChangeSet.stage!(access: @access, name: "create_transaction", arguments: {
      account_id: source.id, name: "Test income", amount: "-10", date: Date.current.iso8601, idempotency_key: "summary-income"
    })
    Mcp::ChangeSet.stage!(access: @access, name: "create_transfer", arguments: {
      source_account_id: source.id, destination_account_id: destination.id, amount: "1", date: Date.current.iso8601, idempotency_key: "summary-transfer"
    })
    Mcp::ChangeSet.stage!(access: @access, name: "create_category", arguments: { name: "Viajes", idempotency_key: "summary-category" })
    Mcp::ChangeSet.stage!(access: @access, name: "create_tag", arguments: { name: "Prueba MCP", idempotency_key: "summary-tag" })
    visit settings_pending_changes_path
    assert_text "2 gastos"
    assert_text "1 ingreso"
    assert_text "1 transferencia"
    assert_text "1 categoría"
    click_link href: settings_pending_change_path(@change_set)
    assert_text "Bankinter Nomina → Bankinter Hipoteca"
    assert_text "Viajes"
    assert_text "Prueba MCP"
    assert_text "10,00"
    assert_text "sin aplicar"
    assert_no_text "Translation missing"
    page.save_screenshot(Rails.root.join("tmp/screenshots/mcp-pending-summary-desktop.png"))
    page.current_window.resize_to(390, 844)
    assert_button "Aprobar cambios"
    assert_text "1 transferencia"
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "Page should not overflow the mobile viewport"
    page.save_screenshot(Rails.root.join("tmp/screenshots/mcp-pending-summary-mobile.png"))
  end
end
