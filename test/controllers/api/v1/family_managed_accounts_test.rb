# frozen_string_literal: true

require "test_helper"

class Api::V1::FamilyManagedAccountsTest < ActionDispatch::IntegrationTest
  setup do
    @manager = users(:family_member)
    @manager.update!(role: :super_admin)
    @partner_account = accounts(:investment)
    @key = ApiKey.create!(user: @manager, name: "Family MCP", scopes: %w[read_write], source: "web", display_key: "family_#{SecureRandom.hex(12)}")
  end

  test "operations list family-managed accounts with full capabilities" do
    invoke("list_accounts", per_page: 100)

    assert_response :success, response.body
    row = response.parsed_body.fetch("data").find { |account| account["id"] == @partner_account.id }
    assert row, "family-managed account should be listed"
    assert row.fetch("family_managed")
    assert_equal @partner_account.owner_id, row.fetch("owner_id")
    assert_equal({ "read" => true, "annotate" => true, "write" => true }, row.fetch("capabilities"))

    own = response.parsed_body.fetch("data").find { |account| account["id"] == accounts(:depository).id }
    assert_not own.fetch("family_managed")
  end

  test "reports leave family-managed accounts out" do
    invoke("get_report_accounts", per_page: 100)

    assert_response :success, response.body
    row = response.parsed_body.fetch("data").find { |account| account["id"] == @partner_account.id }
    assert_not row.fetch("finance_eligible")

    invoke("get_activity_report", start_date: 1.month.ago.to_date.iso8601, end_date: Date.current.iso8601, account_ids: [ @partner_account.id ])
    assert_response :unprocessable_entity
  end

  test "a member cannot reach a super admin's accounts" do
    @manager.update!(role: :member)

    invoke("list_accounts", per_page: 100)

    assert_response :success
    ids = response.parsed_body.fetch("data").map { |account| account["id"] }
    assert_not_includes ids, @partner_account.id
  end

  test "the REST accounts list keeps the personal scope" do
    get "/api/v1/accounts", headers: { "X-Api-Key" => @key.display_key }

    assert_response :success
    assert_not_includes response.body, @partner_account.id
  end

  private
    def invoke(operation, args)
      post "/api/v1/actions/#{operation}", params: { arguments: args }, headers: { "X-Api-Key" => @key.display_key }, as: :json
    end
end
