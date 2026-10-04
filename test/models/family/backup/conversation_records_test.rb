require "test_helper"

class Family::Backup::ConversationRecordsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @source = Family.create!(name: "Historical conversations", currency: "EUR", assistant_type: "external")
    @source_user = @source.users.create!(email: "historical@example.com", password: "password123", role: "admin")
    @target = Family.create!(name: "Conversation destination")
    @target_user = @target.users.create!(email: "conversation-target@example.com", password: "password123", role: "admin")
    @chat = @source_user.chats.create!(title: "Historical question", instructions: "Keep this context", error: { "message" => "Old provider error" })
    @source_user.update_column(:last_viewed_chat_id, @chat.id)
    @message_id = SecureRandom.uuid
    Message.insert_all!([ {
      id: @message_id, chat_id: @chat.id, type: "AssistantMessage", content: "Historical answer",
      ai_model: "openclaw/historical", status: "complete", reasoning: false,
      created_at: Time.current, updated_at: Time.current
    } ])
    ToolCall.insert_all!([ {
      id: SecureRandom.uuid, message_id: @message_id, type: "ToolCall::Function",
      provider_id: "historical-function", function_name: "get_user_info",
      function_arguments: { "detail" => "summary" }, function_result: { "answer" => "Stored result" },
      created_at: Time.current, updated_at: Time.current
    } ])
  end

  test "old conversation types round trip twice without instantiating assistant models" do
    Chat.expects(:instantiate).never
    Message.expects(:instantiate).never
    AssistantMessage.expects(:instantiate).never
    ToolCall.expects(:instantiate).never
    ToolCall::Function.expects(:instantiate).never
    content = Family::Backup.new(@source).generate_ndjson

    assert_no_enqueued_jobs do
      result = Family::DataImporter.new(@target, content).import!
      assert_equal "matched", result[:verification]["status"]
      assert_history(@target)
      second_target = Family.create!(name: "Second destination")
      second_target.users.create!(email: "second-target@example.com", password: "password123", role: "admin")
      reexported = Family::Backup.new(@target).generate_ndjson
      result = Family::DataImporter.new(second_target, reexported).import!
      assert_equal "matched", result[:verification]["status"]
      assert_history(second_target)
    end
  end

  test "restored history remains readable by the current assistant" do
    Family::DataImporter.new(@target, Family::Backup.new(@source).generate_ndjson).import!

    chat = @target_user.reload.chats.sole
    assert_equal "Historical question", chat.title
    assert_equal chat, @target_user.last_viewed_chat
    message = chat.messages.sole
    assert_instance_of AssistantMessage, message
    assert_equal "Historical answer", message.content
    assert_instance_of ToolCall::Function, message.tool_calls.sole
    assert_equal({ "answer" => "Stored result" }, message.tool_calls.sole.function_result)
  end

  test "stopped blank placeholders round trip without jobs or content loss" do
    Message.insert_all!([ {
      id: SecureRandom.uuid, chat_id: @chat.id, type: "AssistantMessage", content: "",
      ai_model: "external-agent", status: "failed", reasoning: false,
      created_at: Time.current, updated_at: Time.current
    } ])

    assert_no_enqueued_jobs do
      result = Family::DataImporter.new(@target, Family::Backup.new(@source).generate_ndjson).import!
      assert_equal "matched", result[:verification]["status"]
    end
    stopped = @target_user.chats.sole.messages.failed.sole
    assert_equal "", stopped.content
    assert_equal "external-agent", stopped.ai_model
    assert_equal "Historical answer", @target_user.chats.sole.messages.complete.sole.content
  end

  test "duplicate conversation IDs are rejected using the stable backup name" do
    content = rewrite_backup do |rows|
      rows << rows.find { |row| row.dig("data", "model") == "Message" }.deep_dup
    end
    assert_no_difference "Message.count" do
      error = assert_raises(Family::Backup::InvalidBackupError) { Family::DataImporter.new(@target, content).import! }
      assert_match(/Duplicate source id Message:/, error.message)
    end
  end

  test "unsupported historical STI types are rejected before restoring rows" do
    %w[Message ToolCall].each do |name|
      content = rewrite_backup do |rows|
        rows.find { |row| row.dig("data", "model") == name }["data"]["attributes"]["type"] = "RemovedOrUnknownType"
      end
      assert_no_difference [ "Chat.count", "Message.count", "ToolCall.count" ] do
        error = assert_raises(Family::Backup::InvalidBackupError) { Family::DataImporter.new(@target, content).import! }
        assert_match(/Invalid historical #{name} type/, error.message)
      end
    end
  end

  test "historical messages cannot refer to chats outside the snapshot" do
    content = rewrite_backup do |rows|
      rows.find { |row| row.dig("data", "model") == "Message" }["data"]["attributes"]["chat_id"] = chats(:one).id
    end
    assert_no_difference "Chat.count" do
      error = assert_raises(Family::Backup::InvalidBackupError) { Family::DataImporter.new(@target, content).import! }
      assert_match(/Missing Chat reference/, error.message)
    end
  end

  private
    def assert_history(family)
      models = Family::Backup.models
      chat = models.fetch("Chat").where(user_id: family.users.select(:id)).sole
      message = models.fetch("Message").where(chat_id: chat.id).sole
      tool = models.fetch("ToolCall").where(message_id: message.id).sole
      assert_equal "Historical question", chat.title
      assert_equal "Keep this context", chat.instructions
      assert_equal({ "message" => "Old provider error" }, chat.error)
      assert_equal chat.id, family.users.sole.last_viewed_chat_id
      assert_equal "AssistantMessage", message.type
      assert_equal "Historical answer", message.content
      assert_equal "ToolCall::Function", tool.type
      assert_equal({ "detail" => "summary" }, tool.function_arguments)
      assert_equal({ "answer" => "Stored result" }, tool.function_result)
    end

    def rewrite_backup
      rows = Family::Backup.new(@source).generate_ndjson.each_line.map { |line| JSON.parse(line) }
      yield rows
      payload = rows.drop(1).map(&:to_json).join("\n")
      rows.first["data"]["sha256"] = Digest::SHA256.hexdigest(payload)
      rows.map(&:to_json).join("\n")
    end
end
