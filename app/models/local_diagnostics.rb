class LocalDiagnostics
  # Identifiers supplied by callers are retained locally; provider payloads and
  # exception backtraces are deliberately excluded from this diagnostic record.
  def self.report(error, source:, level: :error, metadata: {})
    message = error.respond_to?(:message) ? error.message : error.to_s
    details = { error_class: error.class.name }.merge(metadata)

    Rails.logger.public_send(level, "#{source}: #{error.class.name}")

    DebugLogEntry.capture(
      category: "runtime", level: level.to_s, message: message,
      source: source, metadata: details, family_id: metadata[:family_id],
      account_id: metadata[:account_id]
    )
  rescue StandardError
    # Diagnostics must never replace the failure they are reporting.
    nil
  end
end
