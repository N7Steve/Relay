# frozen_string_literal: true

class Api::Operation < ApplicationRecord
  MAX_RESULT_BYTES = 256.kilobytes
  self.table_name = "api_operations"
  belongs_to :user

  # Retries and writes commit atomically, including concurrent requests.
  def self.execute(user:, key:, operation:, arguments:)
    raise Api::Input::Invalid, "idempotency_key must contain 1 to 128 characters" unless key.is_a?(String) && key.length.in?(1..128)

    digest = Digest::SHA256.hexdigest(JSON.generate([ operation, canonical(arguments) ]))
    user.with_lock do
      existing = find_by(user: user, key: key)
      if existing
        raise Api::Input::Invalid, "idempotency_key was already used with different arguments" unless existing.request_digest == digest
        return existing.result
      end
      result = yield.as_json
      if JSON.generate(result).bytesize > MAX_RESULT_BYTES
        raise Api::Input::Invalid, "Write result exceeds 256 KiB; reduce the operation size. No changes were committed."
      end
      create!(user: user, key: key, request_digest: digest, result: result)
      result
    end
  end

  def self.canonical(value)
    case value
    when Hash then value.stringify_keys.sort.to_h.transform_values { |item| canonical(item) }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end
end
