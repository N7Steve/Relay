require "test_helper"

class Mcp::ChangeSetTest < ActiveSupport::TestCase
  test "OAuth renewal preserves the proposal but another client or scope cannot take it over" do
    Mcp::Configuration.stubs(:enabled?).returns(true)
    user = users(:family_admin)
    app = Doorkeeper::Application.create!(name: "Batch client", redirect_uri: "https://example.com/callback", scopes: "read read_write")
    first = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: user.id, scopes: "read_write", expires_in: 600)
    access = Api::Access.new(user: user, scopes: first.scopes.to_a, credential: first)
    receipt = Mcp::ChangeSet.stage!(access: access, name: "create_tag", arguments: { name: "Before renewal", idempotency_key: "oauth-before" })
    set = Mcp::ChangeSet.find(receipt[:change_set_id])
    old_review = set.review_token
    first.revoke
    assert_raises(Api::Access::Forbidden) { set.approve!(actor: user, token: old_review) }
    fresh = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: user.id, scopes: "read_write", expires_in: 600)
    renewed = Api::Access.new(user: user, scopes: fresh.scopes.to_a, credential: fresh)
    Mcp::ChangeSet.refresh_pending_authority!(access: renewed)
    assert_equal fresh.id, set.reload.authority["credential_id"]
    assert_raises(Api::Input::Invalid) { set.approve!(actor: user, token: old_review) }
    other_app = Doorkeeper::Application.create!(name: "Different client", redirect_uri: "https://example.com/callback")
    other = Doorkeeper::AccessToken.create!(application: other_app, resource_owner_id: user.id, scopes: "read_write")
    other_access = Api::Access.new(user: user, scopes: other.scopes.to_a, credential: other)
    assert_not Mcp::ChangeSet.same_connection?(set.authority, other_access.delegated_authority)
    limited = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: user.id, scopes: "read")
    limited_access = Api::Access.new(user: user, scopes: limited.scopes.to_a, credential: limited)
    assert_not Mcp::ChangeSet.same_connection?(set.authority, limited_access.delegated_authority)
    set.approve!(actor: user, token: set.review_token)
    set.apply!
    assert_equal "applied", set.reload.status
  end
end
