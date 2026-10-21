# frozen_string_literal: true

require "test_helper"

class Api::V1::AdministrationOperationsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @key = ApiKey.create!(user: @user, name: "Administration", scopes: %w[read_write], source: "web", display_key: "admin_#{SecureRandom.hex(12)}")
  end

  test "profile and preferences permit named fields and reject privilege injection" do
    invoke("update_profile", first_name: "API name", locale: "es", idempotency_key: "profile")
    assert_response :success, response.body
    assert_equal "API name", @user.reload.first_name
    invoke("update_profile", role: "super_admin", idempotency_key: "escalate")
    assert_response :unprocessable_entity
    invoke("update_preferences", preview_features_enabled: true, theme: "dark", idempotency_key: "prefs")
    assert_response :success
    assert @user.reload.preview_features_enabled?
    invoke("get_security_status", {})
    assert_response :success
    assert_not response.body.include?("otp_secret")
  end

  test "family preferences require family admin and validate currency and timezone" do
    invoke("update_family_settings", name: "Relay group", timezone: "Europe/Madrid", month_start_day: 10, idempotency_key: "family")
    assert_response :success, response.body
    invoke("update_family_settings", currency: "INVALID", idempotency_key: "bad-currency")
    assert_response :unprocessable_entity
    @key.update!(user: users(:family_member))
    invoke("update_family_settings", name: "Denied", idempotency_key: "denied-family")
    assert_response :forbidden
  end

  test "account share preview binds actor permission payload and current ledger state" do
    args = { account_id: accounts(:depository).id, user_id: users(:family_member).id, permission: "read_only" }
    invoke("preview_access_change", args.merge(operation: "update_account_share"))
    assert_response :success, response.body
    token = response.parsed_body.fetch("preview_token")
    invoke("update_account_share", args.merge(permission: "full_control", preview_token: token, idempotency_key: "changed-share"))
    assert_response :unprocessable_entity
    invoke("update_account_share", args.merge(preview_token: token, idempotency_key: "share"))
    assert_response :success, response.body
    assert_equal "read_only", accounts(:depository).account_shares.find_by!(user: users(:family_member)).permission
    @key.update!(user: users(:family_member))
    invoke("set_finance_inclusion", account_id: accounts(:depository).id, included: false, idempotency_key: "finance")
    assert_response :success, response.body
    invoke("preview_access_change", args.merge(operation: "update_account_share"))
    assert_response :forbidden
  end

  test "budget sharing never changes ledger access and requires the owner" do
    args = { user_id: users(:family_member).id, permission: "read_write" }
    invoke("preview_access_change", args.merge(operation: "update_budget_share"))
    assert_response :success, response.body
    token = response.parsed_body.fetch("preview_token")
    before = AccountShare.count
    invoke("update_budget_share", args.merge(preview_token: token, idempotency_key: "budget-share"))
    assert_response :success, response.body
    assert_equal before, AccountShare.count
    assert_equal "read_write", @user.budget_shares_given.find_by!(viewer: users(:family_member)).permission
  end

  test "only instance authority changes member roles and settings and diagnostics never return secrets" do
    invoke("get_instance_status", {})
    assert_response :forbidden
    @user.update!(role: "super_admin")
    args = { user_id: users(:family_member).id, role: "guest" }
    invoke("preview_access_change", args.merge(operation: "update_member_role"))
    assert_response :success, response.body
    token = response.parsed_body.fetch("preview_token")
    invoke("update_member_role", args.merge(preview_token: token, idempotency_key: "role"))
    assert_response :success, response.body
    assert users(:family_member).reload.guest?
    invoke("preview_instance_settings", external_logos_enabled: false)
    token = response.parsed_body.fetch("preview_token")
    invoke("update_instance_settings", external_logos_enabled: false, preview_token: token, idempotency_key: "instance")
    assert_response :success, response.body
    DebugLogEntry.capture(category: "test", level: "error", message: "SECRET_PASSWORD", source: "test", family: @user.family, metadata: { access_token: "SECRET_TOKEN" })
    invoke("list_diagnostics", {})
    assert_response :success
    refute_match(/SECRET_/, response.body)
    invoke("update_instance_settings", smtp_password: "secret", preview_token: token, idempotency_key: "unknown-setting")
    assert_response :unprocessable_entity
  end

  test "credentials and sessions are actor scoped and no stored secret is returned" do
    session = @user.sessions.create!
    other = users(:family_member).sessions.create!
    invoke("list_sessions", {})
    assert_response :success
    assert_not response.parsed_body.fetch("data").any? { |row| row["id"] == other.id }
    invoke("revoke_session", session_id: other.id, idempotency_key: "other-session")
    assert_response :not_found
    invoke("revoke_session", session_id: session.id, idempotency_key: "session")
    assert_response :success
    invoke("list_api_keys", {})
    assert_response :success
    assert_not response.body.include?(@key.display_key)
    invoke("get_human_flow", flow: "api_key")
    assert_response :success
    assert response.parsed_body.fetch("human_required")
  end

  test "invitation preparation does not transfer an existing identity or send mail" do
    assert_no_enqueued_emails do
      invoke("create_invitation", email: "invitee@example.com", role: "member", idempotency_key: "invite")
      assert_response :success, response.body
    end
    id = response.parsed_body.fetch("id")
    assert_not response.body.include?(Invitation.find(id).token)
    invoke("revoke_invitation", invitation_id: id, idempotency_key: "revoke-invite")
    assert_response :success
  end

  test "unlink preserves history and delete requires preview of the selected account" do
    row = accounts(:depository)
    invoke("preview_access_change", operation: "unlink_account", account_id: row.id)
    assert_response :success, response.body
    token = response.parsed_body.fetch("preview_token")
    assert_no_difference "Entry.count" do
      invoke("unlink_account", account_id: row.id, preview_token: token, idempotency_key: "unlink")
      assert_response :success, response.body
    end
    invoke("preview_access_change", operation: "delete_account", account_id: row.id)
    token = response.parsed_body.fetch("preview_token")
    row.update!(notes: "modified after preview")
    invoke("delete_account", account_id: row.id, preview_token: token, idempotency_key: "stale-delete")
    assert_response :unprocessable_entity
  end

  test "human handoffs point at existing native GET routes without pretending to complete consent" do
    @user.update!(role: "super_admin")
    flows = Mcp::Catalog.fetch("get_human_flow").dig(:inputSchema, :properties, :flow, :enum)
    flows.each do |flow|
      args = { flow: flow }
      args[:bank_item_id] = enable_banking_items(:one).id if flow == "bank_authorization"
      args[:account_id] = accounts(:depository).id if flow == "account_lifecycle"
      invoke("get_human_flow", args)
      assert_response :success, "#{flow}: #{response.body}"
      path = response.parsed_body.fetch("path")
      assert path.start_with?("/")
      assert Rails.application.routes.recognize_path(path, method: :get).fetch(:controller).present?, flow
      assert response.parsed_body.fetch("human_required")
    end
  end

  test "background recovery fails closed when runtime is unknown and preserves committed records" do
    @user.update!(role: "super_admin")
    row = @user.family.family_exports.create!(requested_by: @user, status: "pending", updated_at: 2.hours.ago)
    console = mock
    BackgroundJobConsole.stubs(:new).returns(console)
    console.expects(:cancellable?).with(row).returns(false)
    invoke("cancel_background_operation", kind: "backup", record_id: row.id, idempotency_key: "unknown-worker")
    assert_response :unprocessable_entity
    assert row.reload.pending?
    console.expects(:cancellable?).with(row).returns(true)
    invoke("cancel_background_operation", kind: "backup", record_id: row.id, idempotency_key: "lost-worker")
    assert_response :success, response.body
    assert row.reload.failed?
  end

  test "account deletion cannot bypass financial authority over family-wide cascading cleanup" do
    row = accounts(:depository)
    accounts(:investment).update!(owner: users(:family_member))
    accounts(:investment).account_shares.where(user: @user).destroy_all
    invoke("preview_access_change", operation: "delete_account", account_id: row.id)
    assert_response :forbidden
  end

  test "local images use the authorized upload and removing one clears the native icon" do
    file = StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ3sAAAAASUVORK5CYII="))
    file.define_singleton_method(:original_filename) { "icon.png" }
    file.define_singleton_method(:content_type) { "image/png" }
    result = Api::FileTransfer.store!(user: @user, file: file, key: "local-icon", sha256: Digest::SHA256.hexdigest(file.string))
    invoke("set_local_image", kind: "account", account_id: accounts(:depository).id, upload_token: result[:upload_token], idempotency_key: "icon")
    assert_response :success, response.body
    assert accounts(:depository).reload.custom_logo.attached?
    invoke("set_local_image", kind: "account", account_id: accounts(:depository).id, upload_token: nil, idempotency_key: "remove-icon")
    assert_response :success
    assert_not accounts(:depository).reload.custom_logo.attached?
  end

  private
    def invoke(name, args)
      post "/api/v1/actions/#{name}", params: { arguments: args }, headers: { "X-Api-Key" => @key.display_key }, as: :json
    end
end
