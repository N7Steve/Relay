# frozen_string_literal: true

# Static traceability, complementary to behavioral tests and deployment probes.
class Mcp::CoverageAudit
  def self.check!(root: Rails.root, documentation: true)
    matrix = root.join("docs/research/relay-api-capability-matrix.md").read
    expected = matrix.scan(/^\| ([A-Z]{2}-\d{2}) /).flatten.sort
    manifest = YAML.safe_load(root.join("docs/research/relay-api-mcp-coverage.yml").read)
    cases = manifest.fetch("cases")
    errors = []
    errors << "Capability IDs differ from the original matrix" unless cases.keys.sort == expected
    catalog = Mcp::Catalog.all
    mapped = cases.values.flat_map { |row| row.fetch("tools") }.uniq
    errors << "Unmapped tools: #{(catalog.keys - mapped).join(', ')}" unless (catalog.keys - mapped).empty?
    errors << "Unknown mapped tools: #{(mapped - catalog.keys).join(', ')}" unless (mapped - catalog.keys).empty?
    flows = Mcp::Catalog.fetch("get_human_flow").dig(:inputSchema, :properties, :flow, :enum)
    cases.each do |id, row|
      errors << "#{id}: unsupported disposition" unless row["disposition"].in?(%w[implemented mixed excluded presentation_only])
      errors << "#{id}: no implementation or boundary" if row["tools"].empty? && row["limitation"].blank?
      errors << "#{id}: boundary needs a concrete reason" if row["disposition"] != "implemented" && row["limitation"].blank?
      errors << "#{id}: unknown human flow" unless (row.fetch("human_flows", []) - flows).empty?
      errors << "#{id}: no behavioral evidence" if row.fetch("evidence").empty?
      row.fetch("evidence").each { |file| errors << "#{id}: missing evidence #{file}" unless root.join(file).file? }
    end
    routes = Rails.application.routes.routes.select { |route| route.defaults[:controller] == "api/v1/daily_operations" }
    route_names = routes.map { |route| route.defaults[:operation] }
    errors << "Fixed API routes differ from the tool catalog" unless route_names.sort == catalog.keys.sort
    public_methods = Api::DailyOperations.public_instance_methods.map(&:to_s)
    catalog.each_value do |tool|
      name = tool.fetch(:name)
      schema = tool.fetch(:inputSchema)
      errors << "#{name}: missing operation" unless public_methods.include?(name)
      errors << "#{name}: input is open-ended" unless schema[:type] == "object" && schema[:additionalProperties] == false
      errors << "#{name}: structured output missing" unless tool.dig(:outputSchema, :type) == "object"
      errors << "#{name}: write lacks replay key" unless tool.dig(:annotations, :readOnlyHint) || schema.fetch(:required).include?("idempotency_key")
    end
    if documentation
      openapi = YAML.safe_load(root.join("docs/api/openapi.yaml").read, aliases: true)
      catalog.each_key do |name|
        operation = openapi.dig("paths", "/api/v1/actions/#{name}", "post")
        errors << "#{name}: no OpenAPI route" unless operation
        errors << "#{name}: OpenAPI API-key auth missing" unless operation && operation.fetch("security", []).any? { |item| item.key?("apiKeyAuth") }
        errors << "#{name}: no reusable input schema" unless openapi.dig("components", "schemas", "DailyInput#{name.camelize}")
      end
    end
    raise Api::Input::Invalid, errors.join("\n") unless errors.empty?
    { cases: cases.length, tools: catalog.length, routes: routes.length, boundaries: cases.count { |_, row| row["disposition"] != "implemented" } }
  end
end
