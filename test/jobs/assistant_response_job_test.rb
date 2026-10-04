require "test_helper"

class AssistantResponseJobTest < ActiveJob::TestCase
  setup do
    Setting.stubs(:ai_features_enabled?).returns(true)
    @chat = chats(:one)
    @message = @chat.messages.find_by!(type: "UserMessage")
  end

  test "old external jobs stop without dispatching or deleting conversation content" do
    @chat.user.family.update!(assistant_type: "external")
    pending = @chat.messages.create!(type: "AssistantMessage", content: "partial history", ai_model: "external-agent", status: :pending)
    @message.expects(:request_response).never

    assert_no_difference "Message.count" do
      AssistantResponseJob.perform_now(@message, pending)
    end
    assert pending.reload.failed?
    assert_equal "partial history", pending.content
    assert_equal I18n.t("chat.errors.legacy_request_stopped"), @chat.reload.presentable_error_message
  end

  test "blank queued responses stop safely and can be explicitly retried without losing history" do
    prompt = @chat.messages.create!(type: "UserMessage", content: "Queued question", ai_model: "gpt-4.1")
    pending = @chat.messages.where(type: "AssistantMessage", status: :pending).ordered.last
    clear_enqueued_jobs

    AssistantResponseJob.perform_now(prompt, pending)

    assert pending.reload.failed?
    assert_equal "", pending.content
    assert_enqueued_jobs 1, only: AssistantResponseJob do
      @chat.retry_last_message!
    end
    assert AssistantMessage.exists?(pending.id)
    assert @chat.messages.where(type: "AssistantMessage").ordered.last.pending?
  end

  test "old globally external jobs stop even for a builtin family" do
    @message.expects(:request_response).never
    with_env_overrides("ASSISTANT_TYPE" => "external") do
      AssistantResponseJob.perform_now(@message)
    end
    assert @chat.reload.error.present?
  end

  test "new builtin jobs work with a historical external family" do
    @chat.user.family.update!(assistant_type: "external")
    @message.expects(:request_response).with(assistant_message: nil).once
    AssistantResponseJob.perform_now(@message, backend: "builtin")
  end

  test "unmarked jobs stop without guessing their former transport" do
    @message.expects(:request_response).never
    AssistantResponseJob.perform_now(@message)
    assert @chat.reload.error.present?
  end

  test "disabled AI never dispatches marked jobs" do
    @message.expects(:request_response).never
    Setting.stubs(:ai_features_enabled?).returns(false)
    AssistantResponseJob.perform_now(@message, backend: "builtin")
  end
end
