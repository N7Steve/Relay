require "test_helper"

class Api::V1::AiRetirementTest < ActionDispatch::IntegrationTest
  test "retired routes stay unavailable with either API key scope or no credentials" do
    user = users(:family_admin)
    user.api_keys.active.destroy_all
    headers = [ {} ] + %w[read read_write].map do |scope|
      key = ApiKey.create!(user: user, name: "Retirement #{scope}", scopes: [ scope ], source: "web",
                           display_key: ApiKey.generate_secure_key)
      { "X-Api-Key" => key.display_key }
    end

    assert_no_enqueued_jobs do
      headers.each do |api_headers|
        get "/api/v1/chats", headers: api_headers
        assert_response :not_found
        post "/api/v1/chats", headers: api_headers, params: { title: "Removed assistant" }
        assert_response :not_found
        patch "/api/v1/auth/enable_ai", headers: api_headers
        assert_response :not_found
      end
    end
  end
end
