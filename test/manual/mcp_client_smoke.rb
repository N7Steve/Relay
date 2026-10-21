# frozen_string_literal: true

# Run explicitly with the official SDK installed in /tmp/relay-mcp-client.
# This starts only Capybara's temporary test server against relay_test.
require "test_helper"
require "capybara/rails"
require "open3"

class McpClientSmoke < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "official TypeScript client connects paginates reads and writes over HTTP" do
    saved = ENV.to_h.slice("RELAY_MCP_ENABLED", "RELAY_MCP_URL", "RELAY_MCP_API_KEYS_ENABLED", "RELAY_MCP_CLIENT_IDS")
    ENV["RELAY_MCP_ENABLED"] = "true"
    ENV["RELAY_MCP_API_KEYS_ENABLED"] = "true"
    server = Capybara::Server.new(Rails.application, host: "127.0.0.1").boot
    ENV["RELAY_MCP_URL"] = "http://127.0.0.1:#{server.port}/mcp"
    user = users(:family_admin)
    user.update!(preferences: user.preferences.merge("preview_features_enabled" => true))
    application = Doorkeeper::Application.create!(name: "Official MCP SDK", redirect_uri: "https://client.example/callback", confidential: false, scopes: "read_write")
    ENV["RELAY_MCP_CLIENT_IDS"] = application.uid
    token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id, scopes: "read_write", expires_in: 3600, mcp_resource: ENV["RELAY_MCP_URL"])
    key = ApiKey.create!(user: user, name: "SDK smoke", scopes: %w[read_write], source: "web", display_key: "sdk_#{SecureRandom.hex(16)}")
    account = accounts(:depository)
    output, status = Open3.capture2e({ "MCP_URL" => ENV["RELAY_MCP_URL"], "MCP_KEY" => key.display_key, "MCP_BEARER" => token.plaintext_token, "MCP_ACCOUNT" => account.id, "MCP_INVESTMENT" => accounts(:investment).id },
      "node", Rails.root.join("test/manual/mcp_client_smoke.mjs").to_s)
    assert status.success?, output
    assert_includes output, "MCP SDK smoke passed"
    probe, probe_status = Open3.capture2e({ "MCP_CHECK_TOKEN" => token.plaintext_token }, "ruby", Rails.root.join("bin/mcp-deployment-check").to_s, ENV["RELAY_MCP_URL"])
    assert probe_status.success?, probe
    assert_includes probe, "MCP deployment checks passed"
  ensure
    key&.destroy!
    application&.destroy!
    %w[RELAY_MCP_ENABLED RELAY_MCP_URL RELAY_MCP_API_KEYS_ENABLED RELAY_MCP_CLIENT_IDS].each { |name| ENV[name] = saved[name] }
  end
end
