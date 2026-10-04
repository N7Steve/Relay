require "application_system_test_case"

class AssistantRetirementSystemTest < ApplicationSystemTestCase
  test "a stopped request can be explicitly retried while its local history remains" do
    Provider::Github.any_instance.stubs(:fetch_latest_release_notes).returns(nil)
    Provider::Github.any_instance.stubs(:fetch_release_notes).returns(nil)
    Provider::Openai.stubs(:configured?).returns(true)
    Setting.stubs(:ai_features_enabled?).returns(true)
    user = users(:family_admin)
    user.update!(ai_enabled: true)
    chat = user.chats.create!(title: "Retired request")
    prompt = chat.messages.create!(type: "UserMessage", content: "My original question", ai_model: "gpt-4.1")
    stopped = chat.messages.where(type: "AssistantMessage", status: :pending).sole
    AssistantResponseJob.perform_now(prompt, stopped)
    sign_in user

    visit chat_path(chat)
    assert_text I18n.t("chat.errors.legacy_request_stopped")
    assert_no_selector "[data-chat-target='pendingResponse']"
    click_on I18n.t("chats.error.retry"), match: :first
    assert_selector "[data-chat-target='pendingResponse']", count: 1
    assert stopped.reload.failed?
    assert_equal "My original question", prompt.reload.content
  end

  test "hosting keeps builtin configuration and removes external controls for historical families" do
    Provider::Github.any_instance.stubs(:fetch_latest_release_notes).returns(nil)
    Provider::Github.any_instance.stubs(:fetch_release_notes).returns(nil)
    user = users(:family_admin)
    user.family.update!(assistant_type: "external")
    Setting.stubs(:ai_features_enabled?).returns(true)
    sign_in user

    visit settings_hosting_path
    assert_no_selector "a[href='/settings/mcp']", visible: :all
    assert_no_selector "select[name='family[assistant_type]']", visible: :all
    assert_no_selector "input[name='setting[external_assistant_url]']", visible: :all
    assert_selector "input[name='setting[openai_model]']", visible: :all
    page.save_screenshot(Rails.root.join("tmp/screenshots/phase5-hosting.png"))
  end
end
