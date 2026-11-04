# frozen_string_literal: true

# Transport-only contract. REST domain operations keep their existing schemas.
class Mcp::ProposalCatalog
  def self.definitions
    Mcp::Catalog.all.values.map do |definition|
      tool = definition.deep_dup
      if tool[:name] == "get_context"
        tool[:description] += " Call before preparing changes. Returns this installation's operating_instructions: follow its normalization, Agenda exclusions and reconciliation rules."
      end
      tool[:inputSchema] = with_references(tool[:inputSchema], root: true)
      receipt = { type: "object", required: %w[status change_set_id change_id], properties: {
        status: { type: "string" }, change_set_id: Mcp::Catalog::ID, change_id: Mcp::Catalog::ID,
        operation_status: { type: "string" }, approval_path: { type: "string" }, result_reference: { type: "string" }, message: { type: "string" }
      } }
      if definition.dig(:annotations, :readOnlyHint)
        tool[:description] += " Reads canonical data. Pending references defer this read as a step in your proposal."
        tool[:outputSchema] = { type: "object", anyOf: [ definition[:outputSchema], receipt ] }
        if definition[:name].start_with?("preview_")
          tool[:inputSchema][:properties] = tool[:inputSchema][:properties].merge(defer_until_approval: { type: "boolean" }, idempotency_key: Mcp::Catalog::KEY)
          tool[:description] += " For a preview needed by a pending write, set defer_until_approval=true and an idempotency_key, then reference its preview_token in the write."
        end
      else
        tool[:description] = "Propose only: #{definition[:description]} Joins the open proposal for this connection. Prefer propose_changes for independent writes and ask for ONE review at the end of the session in Settings > Pending changes; a human must approve in Relay before it runs. Use pending:<change_id>:<result_field> for results of earlier proposed operations."
        tool[:outputSchema] = receipt
      end
      tool
    end + [ batch_definition, { name: "get_pending_changes", description: "List your MCP proposals and their approval/execution status. Canonical reads do not include proposals. Approval is available only in Relay's web UI.",
      inputSchema: { type: "object", properties: Mcp::Catalog::PAGE, additionalProperties: false }, outputSchema: { type: "object" },
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false } } ]
  end

  def self.batch_schema
    { type: "object", additionalProperties: false, required: %w[operations], properties: {
      operations: { type: "array", minItems: 1, maxItems: Mcp::ChangeSet::MAX_OPERATIONS, items: {
        type: "object", additionalProperties: false, required: %w[name arguments], properties: {
          name: { type: "string", enum: Mcp::Catalog.all.values.reject { |tool| tool.dig(:annotations, :readOnlyHint) }.pluck(:name) },
          arguments: { type: "object" }
        }
      } }
    } }
  end

  def self.batch_definition
    { name: "propose_changes", description: "Prefer this tool for a session's independent writes: stage up to 100 operations together for ONE human approval. Each item has name and arguments (including its own stable idempotency_key). All items are staged or none are. For dependencies, stage creators first and use their pending references in a subsequent batch. Finish the session before asking the user to review the single approval_path.",
      inputSchema: batch_schema, outputSchema: { type: "object" },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false } }
  end

  def self.references?(value)
    case value
    when Hash then value.values.any? { |item| references?(item) }
    when Array then value.any? { |item| references?(item) }
    when String then value.start_with?("pending:")
    else false
    end
  end

  def self.with_references(schema, root: false)
    copy = schema.deep_dup
    if copy[:properties]
      copy[:properties] = copy[:properties].to_h { |key, value| [ key, key.to_s == "idempotency_key" ? value : with_references(value) ] }
    end
    copy[:items] = with_references(copy[:items]) if copy[:items]
    root ? copy : { anyOf: [ copy, { type: "string", pattern: "^pending:[0-9a-f-]{36}:[a-zA-Z_][a-zA-Z_0-9]*(\\.[a-zA-Z_0-9]+)*$", maxLength: 300 } ] }
  end
end
