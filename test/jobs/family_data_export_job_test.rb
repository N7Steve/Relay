require "test_helper"

class FamilyDataExportJobTest < ActiveJob::TestCase
  setup do
    @family = families(:dylan_family)
    @export = @family.family_exports.create!
  end

  test "marks export as processing then completed" do
    assert_equal "pending", @export.status

    perform_enqueued_jobs do
      FamilyDataExportJob.perform_later(@export)
    end

    @export.reload
    assert_equal "completed", @export.status
    assert @export.export_file.attached?
    assert_match(/\Arelay_export_.*\.zip\z/, @export.export_file.filename.to_s)
    Zip::File.open_buffer(@export.export_file.download) do |zip|
      assert_equal "export_version: 2\n", zip.read("version.txt")
      assert SureImport.valid_ndjson_first_line?(zip.read("all.ndjson"))
    end
  end

  test "does not restart an export in a terminal status" do
    @export.update_columns(status: "failed")

    Family::DataExporter.any_instance.expects(:generate_export).never

    perform_enqueued_jobs do
      FamilyDataExportJob.perform_later(@export)
    end

    assert_equal "failed", @export.reload.status
  end

  test "marks export as failed on error" do
    # Mock the exporter to raise an error
    Family::DataExporter.any_instance.stubs(:generate_export).raises(StandardError, "Export failed")

    perform_enqueued_jobs do
      FamilyDataExportJob.perform_later(@export)
    end

    @export.reload
    assert_equal "failed", @export.status
  end
end
