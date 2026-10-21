# frozen_string_literal: true

require "test_helper"

class ApiCredentialIsolationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_member)
    @key = ApiKey.create!(user: @user, name: "Isolation", scopes: [ "read_write" ], display_key: ApiKey.generate_secure_key)
    @app = Doorkeeper::Application.create!(name: "Isolation client", redirect_uri: "https://example.com/callback", scopes: "read read_write")
  end

  test "a rejected bearer never falls back to a different supplied identity" do
    get api_v1_context_url, headers: { "Authorization" => "Bearer invalid", "X-Api-Key" => @key.display_key }
    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body["error"]
  end

  test "OAuth uses the same account capabilities as an API key" do
    token = Doorkeeper::AccessToken.create!(application: @app, resource_owner_id: @user.id, scopes: "read_write")
    get api_v1_account_url(accounts(:credit_card)), headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :success
    assert_equal false, response.parsed_body.dig("capabilities", "write")
    delete api_v1_transaction_url(accounts(:credit_card).entries.transactions.first.entryable_id), headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :forbidden
    token.revoke
    get api_v1_context_url, headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :unauthorized
  end

  test "browser sign in does not supply or replace the API identity" do
    sign_in users(:family_admin)
    get api_v1_context_url
    assert_response :unauthorized
    get api_v1_context_url, headers: api_headers(@key)
    assert_response :success
    assert_equal @user.id, response.parsed_body.dig("user", "id")
    assert_equal false, response.parsed_body.dig("capabilities", "manage_family")
  end
end
