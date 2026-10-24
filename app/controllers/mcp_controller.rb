# frozen_string_literal: true

class McpController < Api::V1::BaseController
  VERSIONS = %w[2026-07-28 2025-11-25].freeze
  MAX_BYTES = 256.kilobytes
  prepend_before_action :check_mcp_access
  skip_around_action :switch_locale
  skip_before_action :restore_active_tabs
  skip_before_action :store_return_to
  rescue_from ActionDispatch::Http::Parameters::ParseError do
    rpc_error(-32700, "Parse error", :bad_request)
  end

  def unsupported
    response.headers["Allow"] = "POST"
    head :method_not_allowed
  end

  def create
    return rpc_error(-32600, "Request too large", :payload_too_large) if request.content_length.to_i > MAX_BYTES
    return rpc_error(-32600, "Content-Type must be application/json", :unsupported_media_type) unless request.media_type == "application/json"
    unless request.headers["Accept"].to_s.include?("application/json") && request.headers["Accept"].to_s.include?("text/event-stream")
      return rpc_error(-32600, "Accept must include application/json and text/event-stream", :not_acceptable)
    end
    raw = request.body.read(MAX_BYTES + 1)
    return rpc_error(-32600, "Request too large", :payload_too_large) if raw.bytesize > MAX_BYTES
    message = JSON.parse(raw, max_nesting: 32)
    unless message.is_a?(Hash) && message["jsonrpc"] == "2.0" && message["method"].is_a?(String) &&
        (!message.key?("id") || message["id"].is_a?(String) || message["id"].is_a?(Integer)) &&
        (!message.key?("params") || message["params"].is_a?(Hash))
      return rpc_error(-32600, "Invalid request", :bad_request)
    end
    @rpc_id = message["id"]
    method, arguments = message.values_at("method", "params")
    arguments ||= {}
    version = request.headers["MCP-Protocol-Version"]
    version ||= arguments["protocolVersion"] if method == "initialize"
    unless VERSIONS.include?(version)
      return rpc_error(-32022, "Unsupported protocol version", :bad_request, { supported: VERSIONS, requested: version })
    end
    if version == "2026-07-28"
      meta = arguments["_meta"]
      unless meta.is_a?(Hash) && meta["io.modelcontextprotocol/protocolVersion"] == version &&
          request.headers["Mcp-Method"] == method &&
          (method != "tools/call" || decoded_header(request.headers["Mcp-Name"]) == arguments["name"])
        return rpc_error(-32020, "HeaderMismatch", :bad_request)
      end
      unless meta["io.modelcontextprotocol/clientInfo"].is_a?(Hash) && meta["io.modelcontextprotocol/clientCapabilities"].is_a?(Hash)
        return rpc_error(-32602, "Client metadata required", :bad_request)
      end
    end
    unless message.key?("id")
      return head :accepted if method.in?(%w[notifications/initialized notifications/cancelled])
      return rpc_error(-32600, "Unsupported notification", :bad_request)
    end

    result = case method
    when "initialize"
      return rpc_error(-32601, "Use server/discover with 2026-07-28", :not_found) unless version == "2025-11-25"
      server_info.merge(protocolVersion: version)
    when "server/discover"
      return rpc_error(-32601, "Method not found", :not_found) unless version == "2026-07-28"
      { supportedVersions: VERSIONS, capabilities: server_info[:capabilities],
        _meta: { "io.modelcontextprotocol/serverInfo" => server_info[:serverInfo] } }
    when "ping" then {}
    when "tools/list" then list_tools(arguments)
    when "tools/call"
      return rpc_error(-32602, "Unknown tool", :bad_request) unless Mcp::Catalog.all.key?(arguments["name"]) || arguments["name"] == "get_pending_changes"
      call_tool(arguments)
    else return rpc_error(-32601, "Method not found", :not_found)
    end
    result = result.merge(resultType: "complete") if version == "2026-07-28"
    render json: { jsonrpc: "2.0", id: @rpc_id, result: result }
  rescue JSON::ParserError
    rpc_error(-32700, "Parse error", :bad_request)
  rescue Api::Input::Invalid => error
    rpc_error(-32602, error.message, :bad_request)
  rescue StandardError => error
    LocalDiagnostics.report(error, metadata: { user_id: Current.user&.id }, source: "mcp")
    rpc_error(-32603, "Internal error", :internal_server_error)
  end

  private
    def check_mcp_access
      Current.reset
      return head :not_found unless Mcp::Configuration.enabled? && Mcp::Configuration.resource.present?
      return head :forbidden unless Mcp::Configuration.origin_allowed?(request.headers["Origin"])
      rpc_error(-32600, "Request too large", :content_too_large) if request.content_length.to_i > MAX_BYTES
    end

    def authenticate_oauth
      return false if request.authorization.blank?
      raw = request.authorization.match(/\ABearer ([^\s]+)\z/i)&.captures&.first
      token = Doorkeeper::AccessToken.by_token(raw)
      return authenticate_authentik(raw) if token.nil? && raw&.include?(".")
      unless token&.accessible? && token.mcp_resource == Mcp::Configuration.resource &&
          Mcp::Configuration.client_allowed?(token.application&.uid) &&
          (token.scopes.to_a & %w[read read_write]).any?
        render_unauthorized
        return false
      end
      @current_user = User.find_by(id: token.resource_owner_id)
      unless @current_user&.active?
        render_unauthorized
        return false
      end
      @_doorkeeper_token = token
      @authentication_method = :oauth
      setup_current_context_for_api
      true
    end

    def authenticate_authentik(raw)
      raise Mcp::Authentik::Invalid unless Mcp::Authentik.enabled?
      @authentik_credential = Mcp::AuthentikVerifier.instance.verify(raw)
      @current_user = @authentik_credential.user
      @authentication_method = :authentik
      setup_current_context_for_api
      true
    rescue Mcp::Authentik::Invalid
      render_unauthorized
      false
    end

    def current_scopes
      @authentication_method == :authentik ? @authentik_credential.scopes : super
    end

    def api_access
      return super unless @authentication_method == :authentik
      @api_access ||= Api::Access.new(user: current_resource_owner, scopes: current_scopes, credential: @authentik_credential)
    end

    def authenticate_api_key
      return false unless ENV["RELAY_MCP_API_KEYS_ENABLED"] == "true"
      super
    end

    def render_unauthorized
      issuer = Mcp::Configuration.resource.delete_suffix("/mcp")
      response.headers["WWW-Authenticate"] = %(Bearer resource_metadata="#{issuer}/.well-known/oauth-protected-resource/mcp")
      super
    end

    def server_info
      { serverInfo: { name: "Relay", version: "1.1.0" }, capabilities: { tools: { listChanged: false } },
        instructions: Mcp::Instructions.text }
    end

    def list_tools(args)
      tools = Mcp::ProposalCatalog.definitions.select { |tool| api_access.writable? || tool[:annotations][:readOnlyHint] }
      cursor = args["cursor"] || "0"
      raise Api::Input::Invalid, "Invalid catalog cursor" unless cursor.is_a?(String) && cursor.match?(/\A\d+\z/) && cursor.to_i <= tools.length
      offset = cursor.to_i
      result = { tools: tools.slice(offset, 25) }
      result[:nextCursor] = (offset + 25).to_s if offset + 25 < tools.length
      result
    end

    def call_tool(args)
      raise Api::Input::Invalid, "Unknown tool" unless Mcp::Catalog.all.key?(args["name"]) || args["name"] == "get_pending_changes"
      raise Api::Input::Invalid, "arguments must be an object" unless args.fetch("arguments", {}).is_a?(Hash)
      name, arguments = args["name"], args.fetch("arguments", {})
      result = if name == "get_pending_changes"
        pending_changes(arguments)
      else
        definition = Mcp::Catalog.fetch(name)
        read = definition.dig(:annotations, :readOnlyHint)
        defer_preview = false
        if read && name.start_with?("preview_")
          Mcp::Catalog.validate!({ type: "boolean" }, arguments["defer_until_approval"]) if arguments.key?("defer_until_approval")
          Mcp::Catalog.validate!(Mcp::Catalog::KEY, arguments["idempotency_key"]) if arguments.key?("idempotency_key")
          defer_preview = arguments["defer_until_approval"] == true
          arguments = arguments.except("defer_until_approval")
        end
        deferred = read && (Mcp::ProposalCatalog.references?(arguments) || defer_preview)
        if read && !deferred
          Api::DailyOperations.new(access: api_access).call(name, name.start_with?("preview_") ? arguments.except("idempotency_key") : arguments)
        else
          if deferred
            arguments = arguments.merge("idempotency_key" => arguments.fetch("idempotency_key", SecureRandom.uuid))
          end
          Mcp::ChangeSet.stage!(access: api_access, name: name, arguments: arguments, deferred_read: deferred)
        end
      end
      result = result.merge(operating_instructions: Mcp::Instructions.text) if name == "get_context"
      encoded = JSON.generate(result)
      if encoded.bytesize > MAX_BYTES
        return tool_error("response_too_large", "Narrow the query or reduce per_page; no records were silently removed")
      end
      { content: [ { type: "text", text: encoded } ], structuredContent: result, isError: false }
    rescue Api::Access::Forbidden
      tool_error("forbidden", "Account permission or credential scope does not allow this operation")
    rescue ActiveRecord::RecordNotFound
      tool_error("not_found", "Resource not found")
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed, Api::Input::Invalid, Money::ConversionError => error
      tool_error("validation_failed", error.message)
    end

    def pending_changes(arguments)
      Mcp::Catalog.validate!({ type: "object", properties: Mcp::Catalog::PAGE, additionalProperties: false }, arguments.deep_stringify_keys)
      page, limit = arguments.fetch("page", 1), arguments.fetch("per_page", 25)
      scope = Mcp::ChangeSet.for_actor(current_resource_owner).order(created_at: :desc)
      count = scope.count
      { data: scope.offset((page - 1) * limit).limit(limit).map(&:overview),
        pagination: { page: page, per_page: limit, total_count: count, next_page: page * limit < count ? page + 1 : nil } }
    end

    def tool_error(code, message)
      { content: [ { type: "text", text: message } ], structuredContent: { error: code, message: message }, isError: true }
    end

    def decoded_header(value)
      if value&.start_with?("=?base64?") && value.end_with?("?=")
        Base64.strict_decode64(value.delete_prefix("=?base64?").delete_suffix("?="))
      else
        value
      end
    rescue ArgumentError
      nil
    end

    def rpc_error(code, message, status, data = nil)
      error = { code: code, message: message }
      error[:data] = data if data
      payload = { jsonrpc: "2.0", error: error }
      payload[:id] = @rpc_id unless @rpc_id.nil? && request.headers["MCP-Protocol-Version"] == "2026-07-28"
      render json: payload, status: status
    end
end
