# frozen_string_literal: true

require "test_helper"

class Api::V1::ContextControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_member)
    @key = ApiKey.create!(user: @user, name: "Context", scopes: [ "read" ], display_key: ApiKey.generate_secure_key)
  end

  test "context describes the credential without granting financial writes" do
    get api_v1_context_url, headers: api_headers(@key)

    assert_response :success
    data = response.parsed_body
    assert_equal @user.id, data.dig("user", "id")
    assert_equal @user.family_id, data.dig("family", "id")
    assert_equal [ "read" ], data.dig("authentication", "scopes")
    assert_equal false, data.dig("capabilities", "write")
    assert_equal false, data.dig("capabilities", "manage_family")
    assert_equal false, data.dig("capabilities", "mcp")
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_not_includes response.body, @key.display_key
  end

  test "write scope does not turn a member into a family administrator" do
    @key.update!(scopes: [ "read_write" ])
    get api_v1_context_url, headers: api_headers(@key)
    assert_response :success
    assert_equal true, response.parsed_body.dig("capabilities", "write")
    assert_equal false, response.parsed_body.dig("capabilities", "manage_family")
  end

  test "requires an active unrevoked credential" do
    get api_v1_context_url
    assert_response :unauthorized
    @key.revoke!
    get api_v1_context_url, headers: api_headers(@key)
    assert_response :unauthorized
  end

  test "account capabilities reflect both token and account permissions" do
    @key.update!(scopes: [ "read_write" ])
    share = account_shares(:credit_card_shared_with_member)
    share.update!(permission: "read_write")
    get api_v1_account_url(share.account), headers: api_headers(@key)
    assert_response :success
    assert_equal({ "read" => true, "annotate" => true, "write" => false }, response.parsed_body.fetch("capabilities"))

    @key.update!(scopes: [ "read" ])
    get api_v1_account_url(share.account), headers: api_headers(@key)
    assert_equal({ "read" => true, "annotate" => false, "write" => false }, response.parsed_body.fetch("capabilities"))
  end
end
