require "test_helper"

class LocalDiagnosticsTest < ActiveSupport::TestCase
  test "records errors locally with identifiers and no backtrace" do
    family = families(:empty)
    error = RuntimeError.new("Sanitized import failure")
    error.set_backtrace([ "secret provider payload" ])

    entry = LocalDiagnostics.report(error, source: "import", metadata: { family_id: family.id, error_class: "ProviderFailure" })

    assert_equal family, entry.family
    assert_equal "Sanitized import failure", entry.message
    assert_equal "ProviderFailure", entry.metadata["error_class"]
    assert_not_includes entry.metadata.to_json, "secret provider payload"
  end

  test "diagnostic persistence failure does not replace the original operation" do
    DebugLogEntry.stubs(:log!).raises(ActiveRecord::ConnectionNotEstablished)
    assert_nil LocalDiagnostics.report(RuntimeError.new("Failure"), source: "import")
  end
end
