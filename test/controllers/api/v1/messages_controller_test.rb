# frozen_string_literal: true

require "test_helper"

class Api::V1::MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider::Openai.stubs(:configured?).returns(true)
    @user = users(:family_admin)
    @user.update!(ai_enabled: true)

    @oauth_app = Doorkeeper::Application.create!(
      name: "Test API App",
      redirect_uri: "https://example.com/callback",
      scopes: "read write read_write"
    )

    @write_token = Doorkeeper::AccessToken.create!(
      application: @oauth_app,
      resource_owner_id: @user.id,
      scopes: "read_write"
    )

    @chat = chats(:one)
  end

  test "should require authentication" do
    post "/api/v1/chats/#{@chat.id}/messages"
    assert_response :unauthorized
  end

  test "should require AI to be enabled" do
    @user.update!(ai_enabled: false)

    post "/api/v1/chats/#{@chat.id}/messages",
      params: { content: "Hello" },
      headers: bearer_auth_header(@write_token)
    assert_response :forbidden
  end

  test "should create message with write scope" do
    assert_difference "UserMessage.count" do
      post "/api/v1/chats/#{@chat.id}/messages",
        params: { content: "Test message", model: "gpt-4" },
        headers: bearer_auth_header(@write_token)
    end

    assert_response :created
    response_body = JSON.parse(response.body)
    assert_equal "Test message", response_body["content"]
    assert_equal "user_message", response_body["type"]
    assert_equal "pending", response_body["ai_response_status"]
  end

  test "should enqueue assistant response job" do
    assert_enqueued_with(job: AssistantResponseJob) do
      post "/api/v1/chats/#{@chat.id}/messages",
        params: { content: "Test message" },
        headers: bearer_auth_header(@write_token)
    end
  end

  test "API key retry reuses the original prompt and preserves failed history" do
    key = ApiKey.create!(user: @user, name: "Retry key", scopes: [ "read_write" ], display_key: "retry_#{SecureRandom.hex(8)}")
    prompt = @chat.messages.create!(type: "UserMessage", content: "Original question", ai_model: "gpt-4.1")
    failed = @chat.messages.where(type: "AssistantMessage", status: :pending).ordered.last
    AssistantResponseJob.perform_now(prompt, failed)
    clear_enqueued_jobs

    assert_difference "AssistantMessage.count", 1 do
      assert_enqueued_jobs 1, only: AssistantResponseJob do
        post "/api/v1/chats/#{@chat.id}/messages/retry", headers: { "X-Api-Key" => key.display_key }
      end
    end

    assert_response :accepted
    pending = @chat.messages.find(response.parsed_body["message_id"])
    assert pending.pending?
    assert_equal prompt.ai_model, pending.ai_model
    assert failed.reload.failed?
    assert_equal "", failed.content
    assert_equal "Original question", prompt.reload.content
  end

  test "read-only API keys cannot retry responses" do
    key = ApiKey.create!(user: @user, name: "Read retry key", scopes: [ "read" ], display_key: "read_retry_#{SecureRandom.hex(8)}")
    assert_no_enqueued_jobs do
      post "/api/v1/chats/#{@chat.id}/messages/retry", headers: { "X-Api-Key" => key.display_key }
    end
    assert_response :forbidden
  end

  test "should not retry if no assistant message exists" do
    # Remove all assistant messages
    @chat.messages.where(type: "AssistantMessage").destroy_all

    post "/api/v1/chats/#{@chat.id}/messages/retry.json",
      headers: bearer_auth_header(@write_token)

    assert_response :unprocessable_entity
    response_body = JSON.parse(response.body)
    assert_equal "No assistant message to retry", response_body["error"]
  end

  test "should not access messages in other user's chat" do
    other_user = users(:family_member)
    other_user.update!(family: families(:empty))
    other_chat = chats(:two)
    other_chat.update!(user: other_user)

    post "/api/v1/chats/#{other_chat.id}/messages",
      params: { content: "Test" },
      headers: bearer_auth_header(@write_token)

    assert_response :not_found
  end

  private

    def bearer_auth_header(token)
      { "Authorization" => "Bearer #{token.token}" }
    end
end
