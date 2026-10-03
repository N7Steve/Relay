require "zip"

# Normalize a portable ZIP or historical NDJSON upload without extracting files.
class SureImport::Upload
  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  def self.read(file)
    new(file).read
  end

  def initialize(file)
    @file = file
  end

  def read
    too_large! if @file.size > SureImport.max_ndjson_size
    extension = File.extname(@file.original_filename.to_s).downcase
    unless extension.in?(%w[.zip .ndjson .json]) || SureImport::ALLOWED_NDJSON_CONTENT_TYPES.include?(@file.content_type)
      raise Error.new("invalid_file_type", "Please upload a backup ZIP or NDJSON file.")
    end

    bytes = @file.read(SureImport.max_ndjson_size + 1) || "".b
    too_large! if bytes.bytesize > SureImport.max_ndjson_size
    if extension == ".zip" || bytes.start_with?("PK\x03\x04".b)
      content = read_zip(bytes)
      [ content, "all.ndjson", "application/x-ndjson" ]
    else
      [ bytes.force_encoding(Encoding::UTF_8), @file.original_filename.presence || "relay-import.ndjson",
        @file.content_type.presence || "application/x-ndjson" ]
    end
  ensure
    @file.rewind
  end

  private
    def read_zip(bytes)
      content = nil
      Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
        entries = zip.entries.select { |entry| entry.name == "all.ndjson" }
        unless entries.one? && !entries.first.directory? && !entries.first.encrypted?
          raise Error.new("invalid_backup", "The backup ZIP must contain one unencrypted all.ndjson file.")
        end
        entry = entries.first
        too_large! if entry.size > SureImport.max_ndjson_size
        stream = entry.get_input_stream
        begin
          content = stream.read(SureImport.max_ndjson_size + 1) || "".b
        ensure
          stream.close
        end
        too_large! if content.bytesize > SureImport.max_ndjson_size
        content.force_encoding(Encoding::UTF_8)
      end
      content
    rescue Zip::Error, Zlib::Error, EOFError
      raise Error.new("invalid_backup", "The backup ZIP is invalid or damaged.")
    end

    def too_large!
      raise Error.new("file_too_large", "Maximum backup size is #{SureImport.max_ndjson_size / 1.megabyte}MB, including decompressed NDJSON.")
    end
end
