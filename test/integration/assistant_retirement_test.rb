require "test_helper"

class AssistantRetirementTest < ActionDispatch::IntegrationTest
  test "MCP discovery registration and settings are absent with legacy credentials" do
    application = Doorkeeper::Application.create!(name: "Retained Client", redirect_uri: "https://client.example.com/callback", scopes: "read_write")
    token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: users(:family_admin).id, scopes: "read_write")
    with_env_overrides("MCP_API_TOKEN" => "legacy", "MCP_USER_EMAIL" => users(:family_admin).email, "ASSISTANT_TYPE" => "external") do
      [ [ :post, "/mcp" ], [ :post, "/register" ],
        [ :get, "/.well-known/oauth-protected-resource" ],
        [ :get, "/.well-known/oauth-authorization-server" ],
        [ :get, "/settings/mcp" ], [ :delete, "/settings/mcp/tokens/#{token.id}" ],
        [ :delete, "/settings/hosting/disconnect_external_assistant" ] ].each do |method, path|
        assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path(path, method: method) }
      end
    end
    assert_nil token.reload.revoked_at
    assert_equal "doorkeeper/tokens", Rails.application.routes.recognize_path("/oauth/token", method: :post)[:controller]
  end

  test "hosting ignores retired settings and keeps historical values" do
    sign_in users(:family_admin)
    family = users(:family_admin).family
    family.update!(assistant_type: "external")
    Setting.external_assistant_url = "https://historic.example.com/chat"
    Setting.external_assistant_token = "historic-token"

    patch settings_hosting_url, params: {
      setting: { external_assistant_url: "https://new.example.com/chat", external_assistant_token: "new-token" },
      family: { assistant_type: "builtin" }
    }
    assert_redirected_to settings_hosting_url
    assert_equal "external", family.reload.assistant_type
    assert_equal "https://historic.example.com/chat", Setting.external_assistant_url
    assert_equal "historic-token", Setting.external_assistant_token

    get settings_hosting_url
    assert_response :success
    assert_select "a[href='/settings/mcp']", count: 0
    assert_select "select[name='family[assistant_type]']", count: 0
    assert_select "input[name='setting[external_assistant_url]']", count: 0
  ensure
    Setting.external_assistant_url = nil
    Setting.external_assistant_token = nil
  end
end
