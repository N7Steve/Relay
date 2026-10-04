require "test_helper"

class AssistantTest < ActiveSupport::TestCase
  include ProviderTestHelper

  test "default registry includes the analytical read tools and gates preview reads" do
    default_classes = Assistant.function_classes

    assert_includes default_classes, Assistant::Function::GetMerchants
    assert_includes default_classes, Assistant::Function::GetRecurringTransactions
    assert_not_includes default_classes, Assistant::Function::GetInsights
    assert_not_includes default_classes, Assistant::Function::GetValuations

    preview_user = users(:family_admin)
    preview_user.update!(preferences: (preview_user.preferences || {}).merge("preview_features_enabled" => true))
    preview_classes = Assistant.function_classes(preview_user)

    assert_includes preview_classes, Assistant::Function::GetInsights
    assert_includes preview_classes, Assistant::Function::GetValuations
  end

  setup do
    @chat = chats(:two)
    @message = @chat.messages.create!(
      type: "UserMessage",
      content: "What is my net worth?",
      ai_model: "gpt-4.1"
    )
    @assistant = Assistant.for_chat(@chat)
    @provider = mock
    @expected_session_id = @chat.id.to_s
    @expected_user_identifier = ::Digest::SHA256.hexdigest(@chat.user_id.to_s)
    @expected_conversation_history = [
      { role: "user", content: "Can you help me understand my spending habits?" },
      { role: "user", content: "What is my net worth?" }
    ]
  end

  test "errors get added to chat" do
    @assistant.expects(:get_model_provider).with("gpt-4.1").returns(@provider)

    error = StandardError.new("test error")
    @provider.expects(:chat_response).returns(provider_error_response(error))

    @chat.expects(:add_error).with(error).once

    assert_no_difference "AssistantMessage.count"  do
      @assistant.respond_to(@message)
    end
  end

  test "handles missing provider gracefully with helpful error message" do
    # Simulate no provider configured (returns nil)
    @assistant.expects(:get_model_provider).with("gpt-4.1").returns(nil)

    # Mock the registry to return empty providers
    mock_registry = mock("registry")
    mock_registry.stubs(:providers).returns([])
    @assistant.stubs(:registry).returns(mock_registry)

    @chat.expects(:add_error).with do |error|
      assert_includes error.message, "No LLM provider configured that supports model 'gpt-4.1'"
      assert_includes error.message, "Please configure an LLM provider (e.g., OpenAI) in settings."
      true
    end

    assert_no_difference "AssistantMessage.count" do
      @assistant.respond_to(@message)
    end
  end

  test "shows available providers in error message when model not supported" do
    # Simulate provider exists but doesn't support the model
    @assistant.expects(:get_model_provider).with("claude-3").returns(nil)

    # Create mock provider
    mock_provider = mock("openai_provider")
    mock_provider.stubs(:provider_name).returns("OpenAI")
    mock_provider.stubs(:supported_models_description).returns("models starting with: gpt-4, gpt-5, o1, o3")

    # Mock the registry to return the provider
    mock_registry = mock("registry")
    mock_registry.stubs(:providers).returns([ mock_provider ])
    @assistant.stubs(:registry).returns(mock_registry)

    # Update message to use unsupported model
    @message.update!(ai_model: "claude-3")

    @chat.expects(:add_error).with do |error|
      assert_includes error.message, "No LLM provider configured that supports model 'claude-3'"
      assert_includes error.message, "Available providers:"
      assert_includes error.message, "OpenAI: models starting with: gpt-4, gpt-5, o1, o3"
      assert_includes error.message, "Use a supported model from the list above"
      true
    end

    assert_no_difference "AssistantMessage.count" do
      @assistant.respond_to(@message)
    end
  end

  test "responds to basic prompt" do
    @assistant.expects(:get_model_provider).with("gpt-4.1").returns(@provider)

    text_chunks = [
      provider_text_chunk("I do not "),
      provider_text_chunk("have the information "),
      provider_text_chunk("to answer that question")
    ]

    response_chunk = provider_response_chunk(
      id: "1",
      model: "gpt-4.1",
      messages: [ provider_message(id: "1", text: text_chunks.join) ],
      function_requests: []
    )

    response = provider_success_response(response_chunk.data)

    @provider.expects(:chat_response).with do |message, **options|
      assert_equal @expected_session_id, options[:session_id]
      assert_equal @expected_user_identifier, options[:user_identifier]
      assert_equal @expected_conversation_history, options[:messages]
      text_chunks.each do |text_chunk|
        options[:streamer].call(text_chunk)
      end

      options[:streamer].call(response_chunk)
      true
    end.returns(response)

    assert_difference "AssistantMessage.count", 1 do
      @assistant.respond_to(@message)
      message = @chat.messages.ordered.where(type: "AssistantMessage").last
      assert_equal "I do not have the information to answer that question", message.content
      assert_equal 0, message.tool_calls.size
    end
  end

  test "responds with tool function calls" do
    @assistant.expects(:get_model_provider).with("gpt-4.1").returns(@provider).once

    Assistant::Function::GetAccounts.any_instance.stubs(:call).returns("test value").once

    call1_response_chunk = provider_response_chunk(
      id: "1",
      model: "gpt-4.1",
      messages: [],
      function_requests: [
        provider_function_request(id: "1", call_id: "1", function_name: "get_accounts", function_args: "{}")
      ]
    )

    call2_text_chunks = [
      provider_text_chunk("Your net worth is "),
      provider_text_chunk("$124,200")
    ]

    call2_response_chunk = provider_response_chunk(
      id: "2",
      model: "gpt-4.1",
      messages: [ provider_message(id: "1", text: call2_text_chunks.join) ],
      function_requests: []
    )

    expect_provider_rounds(
      [ call1_response_chunk ],
      [ *call2_text_chunks, call2_response_chunk ]
    )

    assert_difference "AssistantMessage.count", 1 do
      @assistant.respond_to(@message)
      message = @chat.messages.ordered.where(type: "AssistantMessage").last
      assert_equal "complete", message.status
      assert_equal "Your net worth is $124,200", message.content
      assert_equal 1, message.tool_calls.size
    end
  end

  test "responds after multiple rounds of tool calls" do
    @assistant.expects(:get_model_provider).with("gpt-4.1").returns(@provider).once
    @provider.stubs(:supports_responses_endpoint?).returns(false)

    Assistant::Function::GetAccounts.any_instance.stubs(:call).returns("accounts").twice
    Assistant::Function::GetIncomeStatement.any_instance.stubs(:call).returns("income").once

    first_tools = provider_response_chunk(
      id: "1",
      model: "gpt-4.1",
      messages: [],
      function_requests: [
        provider_function_request(id: "1", call_id: "1", function_name: "get_accounts", function_args: "{}")
      ]
    )
    second_tools = provider_response_chunk(
      id: "2",
      model: "gpt-4.1",
      messages: [],
      function_requests: [
        provider_function_request(id: "2", call_id: "2", function_name: "get_income_statement", function_args: "{}"),
        provider_function_request(id: "2", call_id: "3", function_name: "get_accounts", function_args: "{}")
      ]
    )
    final_text = provider_text_chunk("Final answer.")
    final_response = provider_response_chunk(
      id: "3",
      model: "gpt-4.1",
      messages: [ provider_message(id: "3", text: final_text.data) ],
      function_requests: []
    )

    expect_provider_rounds(
      [ first_tools ],
      [ second_tools ],
      [ final_text, final_response ],
      expected_function_result_ids: [ [], [ "1" ], [ "1", "2", "3" ] ]
    )

    assert_difference "AssistantMessage.count", 1 do
      @assistant.respond_to(@message)
    end

    response = @chat.messages.ordered.where(type: "AssistantMessage").last
    assert_equal "complete", response.status
    assert_equal "Final answer.", response.content
    assert_equal [ "get_accounts", "get_accounts", "get_income_statement" ],
                 response.tool_calls.map(&:function_name).sort
  end

  test "keeps earlier text when the final tool follow-up is empty" do
    @assistant.expects(:get_model_provider).with("gpt-4.1").returns(@provider).once
    Assistant::Function::GetAccounts.any_instance.stubs(:call).returns("accounts").once

    partial_text = provider_text_chunk("I found your accounts.")
    tools_with_text = provider_response_chunk(
      id: "1",
      model: "gpt-4.1",
      messages: [ provider_message(id: "1", text: partial_text.data) ],
      function_requests: [
        provider_function_request(id: "1", call_id: "1", function_name: "get_accounts", function_args: "{}")
      ]
    )
    empty_follow_up = provider_response_chunk(
      id: "2",
      model: "gpt-4.1",
      messages: [],
      function_requests: []
    )

    expect_provider_rounds(
      [ partial_text, tools_with_text ],
      [ empty_follow_up ]
    )

    @assistant.respond_to(@message)

    response = @chat.messages.ordered.where(type: "AssistantMessage").last
    assert_equal "complete", response.status
    assert_equal "I found your accounts.", response.content
    assert_equal 1, response.tool_calls.size
  end

  test "cleans up the pending message when the tool-call limit is exceeded" do
    @assistant.expects(:get_model_provider).with("gpt-4.1").returns(@provider).once
    Assistant::Function::GetAccounts.any_instance.stubs(:call).returns("accounts").once

    first_tools = provider_response_chunk(
      id: "1",
      model: "gpt-4.1",
      messages: [],
      function_requests: [
        provider_function_request(id: "1", call_id: "1", function_name: "get_accounts", function_args: "{}")
      ]
    )
    second_tools = provider_response_chunk(
      id: "2",
      model: "gpt-4.1",
      messages: [],
      function_requests: [
        provider_function_request(id: "2", call_id: "2", function_name: "get_accounts", function_args: "{}")
      ]
    )

    expect_provider_rounds([ first_tools ], [ second_tools ])
    pending = AssistantMessage.create!(chat: @chat, content: "", ai_model: @message.ai_model, status: :pending)

    with_env_overrides("ASSISTANT_MAX_TOOL_CALL_ITERATIONS" => "1") do
      @assistant.respond_to(@message, assistant_message: pending)
    end

    assert_not AssistantMessage.exists?(pending.id)
    assert_includes @chat.reload.technical_error_message, "tool-call limit"
  end

  test "cleans up the pending message when the model returns no text or tools" do
    @assistant.expects(:get_model_provider).with("gpt-4.1").returns(@provider).once

    empty_response = provider_response_chunk(
      id: "1",
      model: "gpt-4.1",
      messages: [],
      function_requests: []
    )

    expect_provider_rounds([ empty_response ])
    pending = AssistantMessage.create!(chat: @chat, content: "", ai_model: @message.ai_model, status: :pending)

    @assistant.respond_to(@message, assistant_message: pending)

    assert_not AssistantMessage.exists?(pending.id)
    assert_includes @chat.reload.technical_error_message, "neither text nor tool calls"
  end

  test "for_chat returns Builtin by default" do
    assert_instance_of Assistant::Builtin, Assistant.for_chat(@chat)
  end

  test "retired routing settings cannot select an external assistant" do
    @chat.user.family.update!(assistant_type: "external")
    with_env_overrides("ASSISTANT_TYPE" => "external", "EXTERNAL_ASSISTANT_URL" => "https://retired.example.com/chat") do
      assert_instance_of Assistant::Builtin, Assistant.for_chat(@chat)
    end
  end

  test "available_types only includes builtin" do
    assert_includes Assistant.available_types, "builtin"
    assert_equal [ "builtin" ], Assistant.available_types
  end

  test "ASSISTANT_TYPE env override with unknown value falls back to builtin" do
    with_env_overrides("ASSISTANT_TYPE" => "nonexistent") do
      assert_instance_of Assistant::Builtin, Assistant.for_chat(@chat)
    end
  end

  test "for_chat raises when chat is blank" do
    assert_raises(Assistant::Error) { Assistant.for_chat(nil) }
  end

  test "builtin demotes a partially-streamed assistant message to failed on error" do
    @assistant.expects(:get_model_provider).with("gpt-4.1").returns(@provider)

    boom = StandardError.new("boom mid-stream")

    @provider.expects(:chat_response).with do |_prompt, **options|
      # Simulate a partial text chunk landing before the error propagates.
      options[:streamer].call(provider_text_chunk("partial tokens "))
      true
    end.returns(provider_error_response(boom))

    @assistant.respond_to(@message)

    partial = @chat.messages.where(type: "AssistantMessage").order(:created_at).last
    assert partial.present?, "partial assistant message should be persisted"
    assert_equal "failed", partial.status
    assert_equal "partial tokens ", partial.content
  end

  test "conversation_history excludes failed and pending messages" do
    # Add a failed assistant turn; it must NOT leak into history.
    AssistantMessage.create!(
      chat: @chat,
      content: "partial error response",
      ai_model: "gpt-4.1",
      status: "failed"
    )

    @assistant.expects(:get_model_provider).with("gpt-4.1").returns(@provider)

    captured_history = nil
    @provider.expects(:chat_response).with do |_prompt, **options|
      captured_history = options[:messages]
      options[:streamer].call(
        provider_response_chunk(id: "1", model: "gpt-4.1", messages: [ provider_message(id: "1", text: "ok") ], function_requests: [])
      )
      true
    end.returns(provider_success_response(
      provider_response_chunk(id: "1", model: "gpt-4.1", messages: [ provider_message(id: "1", text: "ok") ], function_requests: []).data
    ))

    @assistant.respond_to(@message)

    contents = captured_history.map { |m| m[:content] }
    assert_not_includes contents, "partial error response"
  end

  test "conversation_history serializes assistant tool_calls with paired tool result" do
    assistant_msg = AssistantMessage.create!(
      chat: @chat,
      content: "Looking that up",
      ai_model: "gpt-4.1",
      status: "complete"
    )

    ToolCall::Function.create!(
      message: assistant_msg,
      provider_id: "call_abc",
      provider_call_id: "call_abc",
      function_name: "get_net_worth",
      function_arguments: { foo: "bar" },
      function_result: { amount: 1000, currency: "USD" }
    )

    @assistant.expects(:get_model_provider).with("gpt-4.1").returns(@provider)

    captured_history = nil
    @provider.expects(:chat_response).with do |_prompt, **options|
      captured_history = options[:messages]
      options[:streamer].call(
        provider_response_chunk(id: "1", model: "gpt-4.1", messages: [ provider_message(id: "1", text: "ok") ], function_requests: [])
      )
      true
    end.returns(provider_success_response(
      provider_response_chunk(id: "1", model: "gpt-4.1", messages: [ provider_message(id: "1", text: "ok") ], function_requests: []).data
    ))

    @assistant.respond_to(@message)

    tool_call_entry = captured_history.find { |m| m[:role] == "assistant" && m[:tool_calls].present? }
    tool_result_entry = captured_history.find { |m| m[:role] == "tool" }

    assert_not_nil tool_call_entry, "tool_call message missing from history"
    assert_not_nil tool_result_entry, "tool_result message missing from history"
    assert_equal "call_abc", tool_call_entry[:tool_calls].first[:id]
    assert_equal "call_abc", tool_result_entry[:tool_call_id]
    assert_not tool_result_entry.key?(:name), "tool messages must not carry the deprecated `name` field"
  end

  private


    def pending_assistant_message
      @chat.messages.where(type: "AssistantMessage", status: "pending").order(:created_at).last
    end

    def provider_function_request(id:, call_id:, function_name:, function_args:)
      Provider::LlmConcept::ChatFunctionRequest.new(
        id: id,
        call_id: call_id,
        function_name: function_name,
        function_args: function_args
      )
    end

    def provider_message(id:, text:)
      Provider::LlmConcept::ChatMessage.new(id: id, output_text: text)
    end

    def provider_text_chunk(text)
      Provider::LlmConcept::ChatStreamChunk.new(type: "output_text", data: text, usage: nil)
    end

    def provider_response_chunk(id:, model:, messages:, function_requests:, usage: nil)
      Provider::LlmConcept::ChatStreamChunk.new(
        type: "response",
        data: Provider::LlmConcept::ChatResponse.new(
          id: id,
          model: model,
          messages: messages,
          function_requests: function_requests
        ),
        usage: usage
      )
    end

    def expect_provider_rounds(*rounds, expected_function_result_ids: nil)
      queued_rounds = rounds.dup
      queued_result_ids = expected_function_result_ids&.dup
      responses = rounds.map do |chunks|
        response_chunk = chunks.find { |chunk| chunk.type == "response" }
        provider_success_response(response_chunk.data)
      end

      @provider.expects(:chat_response).times(rounds.length).with do |_message, **options|
        assert_equal @expected_session_id, options[:session_id]
        assert_equal @expected_user_identifier, options[:user_identifier]
        assert_equal @expected_conversation_history, options[:messages]
        if queued_result_ids
          assert_equal queued_result_ids.shift, options[:function_results].map { |result| result[:call_id] }
        end
        chunks = queued_rounds.shift
        chunks.each { |chunk| options[:streamer].call(chunk) }
        true
      end.returns(*responses)
    end
end
