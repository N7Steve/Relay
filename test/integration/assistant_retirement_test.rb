require "test_helper"

class AssistantRetirementTest < ActionDispatch::IntegrationTest
  test "retired AI routes cannot be activated by historical credentials" do
    sign_in users(:family_admin)
    ClimateControl.modify("OPENAI_ACCESS_TOKEN" => "legacy", "ANTHROPIC_API_KEY" => "legacy", "JEV_API_KEY" => "legacy") do
      [ [ :get, "/chats" ], [ :post, "/chats" ], [ :get, "/api/v1/chats" ],
        [ :post, "/api/v1/chats" ], [ :patch, "/api/v1/auth/enable_ai" ],
        [ :get, "/settings/ai_prompts" ], [ :get, "/settings/llm_usage" ],
        [ :get, "/admin/system_health/ai_status" ], [ :post, "/admin/system_health/verify_worker_ai" ] ].each do |method, path|
        public_send(method, path)
        assert_response :not_found
      end
      assert_not Setting.ai_features_enabled?
      assert_not users(:family_admin).ai_enabled?
    end
  end

  test "legacy preference writes cannot enable AI or change retired credentials" do
    sign_in users(:family_admin)
    assert_no_enqueued_jobs do
      patch settings_hosting_url, params: { setting: { ai_features_enabled: "1", openai_access_token: "new-token" } }
    end
    assert_redirected_to settings_hosting_url
    assert_not Setting.ai_features_enabled?
    assert_not Setting.exists?(var: "openai_access_token")
  end

  test "PDF and direct document import requests are rejected without creating records" do
    sign_in users(:family_admin)
    assert_no_difference [ "Import.count", "AccountStatement.count", "FamilyDocument.count" ] do
      assert_no_enqueued_jobs do
        post imports_url, params: { import: { type: "PdfImport" } }
        assert_response :forbidden
        post imports_url, params: { import: { type: "DocumentImport" } }
        assert_response :forbidden
        post imports_url, params: { import: { import_file: file_fixture_upload("imports/sample_bank_statement.pdf", "application/pdf") } }
        assert_response :forbidden
      end
    end
  end

  test "retired response jobs remain sinks without conversation persistence" do
    assert_not users(:family_admin).respond_to?(:chats)
    assert_nil "Chat".safe_constantize
    assert_no_enqueued_jobs do
      AssistantResponseJob.perform_now("retired-prompt", "retired-response", backend: "builtin")
    end
  end

  test "queued PDF extraction fails locally while preserving original bytes" do
    pdf_import = PdfImport.create!(family: families(:dylan_family))
    pdf_import.pdf_file.attach(io: StringIO.new("%PDF-preserved"), filename: "original.pdf", content_type: "application/pdf")
    pdf_import.update!(status: :importing)
    ProcessPdfJob.perform_now(pdf_import)
    assert pdf_import.reload.failed?
    assert_equal "%PDF-preserved", pdf_import.pdf_file.download
    assert_match(/retired/, pdf_import.error)
  end
end
