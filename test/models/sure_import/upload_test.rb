require "test_helper"

class SureImport::UploadTest < ActiveSupport::TestCase
  test "reads Sure and Relay ZIP filenames through their all.ndjson entry" do
    content = Family::Backup.new(families(:empty)).generate_ndjson
    %w[sure_export.zip relay_export.zip].each do |filename|
      upload = zip_upload(filename, "all.ndjson" => content, "ignored.csv" => "not imported")
      assert_equal [ content, "all.ndjson", "application/x-ndjson" ], SureImport::Upload.read(upload)
    end
  end

  test "rejects malformed ZIPs and missing root all.ndjson without extracting paths" do
    [ zip_upload("backup.zip", "../all.ndjson" => "{}"),
      uploaded_file("backup.zip", "not a ZIP", "application/zip") ].each do |upload|
      error = assert_raises(SureImport::Upload::Error) { SureImport::Upload.read(upload) }
      assert_equal "invalid_backup", error.code
    end
  end

  test "limits decompressed NDJSON even when its ZIP fits the upload limit" do
    upload = zip_upload("backup.zip", "all.ndjson" => "a" * 20_000)
    SureImport.stubs(:max_ndjson_size).returns(1000)
    assert_operator upload.size, :<, 1000
    error = assert_raises(SureImport::Upload::Error) { SureImport::Upload.read(upload) }
    assert_equal "file_too_large", error.code
  end

  test "continues accepting NDJSON and rewinds the upload" do
    content = '{"type":"Account","data":{"name":"Test"}}'
    upload = uploaded_file("legacy.ndjson", content, "application/x-ndjson")
    assert_equal content, SureImport::Upload.read(upload).first
    assert_equal content, upload.read
  end

  private
    def zip_upload(filename, entries)
      bytes = Zip::OutputStream.write_buffer do |zip|
        entries.each do |name, content|
          zip.put_next_entry(name)
          zip.write(content)
        end
      end.string
      uploaded_file(filename, bytes, "application/zip")
    end

    def uploaded_file(filename, bytes, content_type)
      tempfile = Tempfile.new("backup-upload")
      tempfile.binmode
      tempfile.write(bytes)
      tempfile.rewind
      ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: filename, type: content_type)
    end
end
