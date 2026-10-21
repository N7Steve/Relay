# frozen_string_literal: true

# A durable proposal, not a simulation: domain methods run only after web approval.
class Mcp::ChangeSet < ApplicationRecord
  self.table_name = "mcp_change_sets"
  belongs_to :user
  belongs_to :family

  MAX_OPERATIONS = 100
  MAX_BYTES = 2.megabytes
  REFERENCE = /\Apending:([0-9a-f-]{36}):([a-zA-Z_][a-zA-Z_0-9]*(?:\.[a-zA-Z_0-9]+)*)\z/
  STATUSES = %w[pending approved applying applied failed rejected].freeze
  validates :status, inclusion: { in: STATUSES }
  scope :for_actor, ->(actor) { where(user: actor, family_id: actor.family_id) }

  def self.stage!(access:, name:, arguments:, deferred_read: false)
    raise Api::Access::Forbidden, "Write scope required" unless access.writable?
    definition = Mcp::Catalog.fetch(name)
    if definition.dig(:annotations, :readOnlyHint) && !deferred_read
      raise Api::Input::Invalid, "Read steps must be explicitly deferred"
    end
    args = arguments.deep_stringify_keys
    authority = access.delegated_authority
    raise Api::Access::Forbidden, "An active credential is required" unless authority["credential_id"]

    access.user.with_lock do
      sets = for_actor(access.user)
      # A retry must keep its original proposal even after approval or rejection.
      previous = sets.where("operations @> ?::jsonb", [ { arguments: { idempotency_key: args["idempotency_key"] } } ].to_json).first if args["idempotency_key"].is_a?(String)
      if previous
        operation = previous.operations.find { |row| row.dig("arguments", "idempotency_key") == args["idempotency_key"] }
        unless previous.authority == authority && operation["name"] == name && operation["arguments"] == args
          raise Api::Input::Invalid, "idempotency_key was already used with different arguments or a different credential"
        end
        return previous.receipt(operation)
      end
      set = sets.where(status: "pending", authority: authority).order(:created_at).first || new(user: access.user, family: access.user.family, authority: authority,
        credential_name: access.credential_label)
      schema = definition.fetch(:inputSchema)
      if deferred_read
        schema = schema.merge(properties: schema.fetch(:properties).merge(idempotency_key: Mcp::Catalog::KEY))
      end
      set.validate_arguments!(schema, args)
      raise Api::Input::Invalid, "This proposal is full; review it in Relay before proposing more changes" if set.operations.size >= MAX_OPERATIONS
      operation = { "id" => SecureRandom.uuid, "name" => name, "arguments" => args, "status" => "pending" }
      set.operations = set.operations + [ operation ]
      raise Api::Input::Invalid, "This proposal exceeds 2 MiB; review it in Relay first" if set.operations.to_json.bytesize > MAX_BYTES
      set.save!
      set.receipt(operation)
    end
  end

  def receipt(operation)
    { status: status == "pending" ? "pending_approval" : status, change_set_id: id, change_id: operation.fetch("id"),
      operation_status: operation.fetch("status"), approval_path: "/settings/pending_changes/#{id}",
      result_reference: "pending:#{operation.fetch('id')}:id",
      message: "This is a proposal. No domain change is made before approval in Relay. References use pending:<change_id>:<result_field>." }
  end

  def review_token
    self.class.verifier.generate({ "id" => id, "user_id" => user_id, "digest" => review_digest }, purpose: "mcp_review", expires_in: 1.hour)
  end

  def approve!(actor:, token:)
    actor.with_lock do
      with_lock do
        verify_review!(actor, token)
        raise Api::Input::Invalid, "Only pending proposals can be approved" unless status == "pending"
        Api::Access.from_delegation!(authority, family: family)
        update!(status: "approved", approved_at: Time.current)
        Mcp::ApplyChangeSetJob.perform_later(self)
      end
    end
  end

  def reject!(actor:, token:)
    actor.with_lock do
      with_lock do
        verify_review!(actor, token)
        raise Api::Input::Invalid, "Only pending or failed proposals can be rejected" unless status.in?(%w[pending failed])
        update!(status: "rejected", finished_at: Time.current)
      end
    end
  end

  # Each domain operation and its completion marker commit together. A job retry
  # resumes without repeating completed operations or remote side effects.
  def apply!
    loop do
      continue = user.with_lock do
        with_lock do
          next false unless status.in?(%w[approved applying])
          index = operations.index { |operation| operation["status"] == "pending" }
          unless index
            update!(status: "applied", finished_at: Time.current)
            next false
          end
          operation = operations.fetch(index)
          access = Api::Access.from_delegation!(authority, family: family)
          raise Api::Access::Forbidden, "MCP is no longer enabled" unless Mcp::Configuration.enabled?
          if authority["credential_type"] == "ApiKey" && ENV["RELAY_MCP_API_KEYS_ENABLED"] != "true"
            raise Api::Access::Forbidden, "MCP API keys are no longer enabled"
          end
          args = resolve_references(operation.fetch("arguments"))
          # A separate replay namespace prevents pre-existing REST operations
          # from being mistaken for execution of this approved proposal.
          if Mcp::Catalog.fetch(operation.fetch("name")).dig(:annotations, :readOnlyHint)
            args = args.except("idempotency_key")
          else
            args["idempotency_key"] = "mcp-approved:#{operation.fetch('id')}"
          end
          result = Current.set(session: access.user.sessions.build) do
            Time.use_zone(family.timezone) do
              Api::DailyOperations.new(access: access).call(operation.fetch("name"), args)
            end
          end
          if JSON.generate(result).bytesize > Api::Operation::MAX_RESULT_BYTES
            raise Api::Input::Invalid, "Deferred result exceeds 256 KiB; narrow the query"
          end
          rows = operations.deep_dup
          rows[index] = operation.merge("status" => "applied", "result" => result.as_json)
          update!(status: "applying", operations: rows)
          true
        end
      end
      break unless continue
    end
  rescue StandardError => error
    with_lock do
      if status.in?(%w[approved applying])
        rows = operations.deep_dup
        row = rows.find { |operation| operation["status"] == "pending" }
        expected = error.is_a?(Api::Input::Invalid) || error.is_a?(Api::Access::Forbidden) || error.is_a?(ActiveRecord::RecordInvalid) || error.is_a?(ActiveRecord::RecordNotFound)
        row&.merge!("status" => "failed", "error" => error.class.name,
          "error_message" => expected ? error.message.truncate(1000) : "Operation failed; consult local diagnostics")
        update!(status: "failed", operations: rows, finished_at: Time.current)
      end
    end
    DebugLogEntry.capture(message: "MCP approved proposal failed", category: "mcp", level: "error", source: self.class.name, family: family,
      metadata: { change_set_id: id, error_class: error.class.name })
  end

  def overview
    { id: id, status: status, created_at: created_at.iso8601, counts: operation_counts,
      applied: operations.count { |operation| operation["status"] == "applied" },
      total: operations.size, failure: operations.find { |row| row["status"] == "failed" }&.slice("name", "error", "error_message"),
      approval_path: "/settings/pending_changes/#{id}" }
  end

  def operation_counts
    operations.group_by { |row| self.class.action_for(row.fetch("name")) }.transform_values(&:size)
  end

  def operation_groups
    operations.group_by { |row| [ self.class.action_for(row.fetch("name")), self.class.domain_for(row.fetch("name")) ] }
      .map { |(action, domain), rows| { action: action, domain: domain, count: rows.size } }
  end

  def self.action_for(name)
    return "prepare" if Mcp::Catalog.fetch(name).dig(:annotations, :readOnlyHint)
    return "delete" if name.match?(/\A(delete|remove|revoke|disconnect|unlink|bulk_delete|reject|cancel)_/)
    return "create" if name.match?(/\A(create|duplicate|upload|start_import|start_import_session|restore_backup)_/)
    "update"
  end

  def self.domain_for(name)
    case name
    when /profile|preferences/ then "settings"
    when /import|statement|attachment|backup|file/ then "files"
    when /transaction|transfer|trade|holding|valuation|security|price|exchange|reconcil|portfolio/ then "movements"
    when /account/ then "accounts"
    when /budget|rollover/ then "budgets"
    when /goal|pledge/ then "goals"
    when /scheduled|occurrence/ then "agenda"
    when /category|merchant|tag|rule/ then "organization"
    when /bank|drive|sync/ then "integrations"
    else "settings"
    end
  end

  def validate_arguments!(schema, args)
    raise Api::Input::Invalid, "idempotency_key cannot be a pending reference" if args["idempotency_key"].to_s.start_with?("pending:")
    validate_node!(schema.deep_stringify_keys, args)
  end

  private
    def self.verifier
      Rails.application.message_verifier("mcp_change_set_review")
    end

    def review_digest
      Digest::SHA256.hexdigest(operations.to_json)
    end

    def verify_review!(actor, token)
      raise Api::Access::Forbidden, "Proposal belongs to another user or family" unless actor.active? && actor.id == user_id && actor.family_id == family_id
      data = self.class.verifier.verified(token, purpose: "mcp_review")
      unless data && data["id"] == id && data["user_id"] == actor.id && data["digest"] == review_digest
        raise Api::Input::Invalid, "Proposal changed or review expired; reload before deciding"
      end
    end

    def validate_node!(schema, value)
      if value.is_a?(String) && value.start_with?("pending:")
        match = REFERENCE.match(value)
        unless match && operations.any? { |operation| operation["id"] == match[1] }
          raise Api::Input::Invalid, "Pending references must name an earlier operation in this proposal"
        end
        raise Api::Input::Invalid, "Pending reference is too long" if value.length > 300
        return
      end
      if value.is_a?(Hash)
        raise Api::Input::Invalid, "Invalid argument type" unless Array(schema["type"]).include?("object")
        properties = schema.fetch("properties", {})
        raise Api::Input::Invalid, "Arguments contain unknown fields" if schema["additionalProperties"] == false && (value.keys - properties.keys).any?
        raise Api::Input::Invalid, "Arguments are missing required fields" if (schema.fetch("required", []) - value.keys).any?
        value.each { |key, item| validate_node!(properties[key], item) if properties[key] }
      elsif value.is_a?(Array)
        unless Array(schema["type"]).include?("array") && value.length.between?(schema.fetch("minItems", 0), schema.fetch("maxItems", 100))
          raise Api::Input::Invalid, "Invalid array argument"
        end
        raise Api::Input::Invalid, "Array must contain unique items" if schema["uniqueItems"] && value.uniq.size != value.size
        value.each { |item| validate_node!(schema.fetch("items"), item) }
      else
        Mcp::Catalog.validate!(schema, value)
      end
    end

    def resolve_references(value)
      case value
      when Hash then value.transform_values { |item| resolve_references(item) }
      when Array then value.map { |item| resolve_references(item) }
      when String
        match = REFERENCE.match(value)
        return value unless match
        operation = operations.find { |row| row["id"] == match[1] && row["status"] == "applied" }
        raise Api::Input::Invalid, "Pending reference has not been applied" unless operation
        match[2].split(".").reduce(operation.fetch("result")) do |result, key|
          if result.is_a?(Hash) && result.key?(key)
            result.fetch(key)
          elsif result.is_a?(Array) && key.match?(/\A\d+\z/) && key.to_i < result.size
            result.fetch(key.to_i)
          else
            raise Api::Input::Invalid, "Pending result field does not exist"
          end
        end
      else value
      end
    end
end
