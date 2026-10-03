require "base64"
require "digest"
require "json"
require "net/http"
require "openssl"
require "securerandom"
require "uri"

class GoogleDrive::Client
  AUTHORIZE_URL = "https://accounts.google.com/o/oauth2/v2/auth"
  TOKEN_URL = "https://oauth2.googleapis.com/token"
  REVOKE_URL = "https://oauth2.googleapis.com/revoke"
  USER_INFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"
  DRIVE_API_URL = "https://www.googleapis.com/drive/v3"
  DRIVE_UPLOAD_URL = "https://www.googleapis.com/upload/drive/v3"
  SCOPES = %w[openid email https://www.googleapis.com/auth/drive.file].freeze
  REQUEST_TIMEOUT = 30

  Error = Class.new(StandardError)
  ConfigurationError = Class.new(Error)
  AuthenticationError = Class.new(Error)
  PermissionError = Class.new(Error)
  FileMissingError = Class.new(Error)
  TransientError = Class.new(Error)
  ApiError = Class.new(Error)

  class << self
    def configured?(configuration: nil)
      return false unless ExternalAccess.enabled?(:google_drive)
      client_id(configuration: configuration).present? && client_secret(configuration: configuration).present?
    end

    def client_id(configuration: nil)
      configuration&.client_id.presence || ENV["GOOGLE_DRIVE_CLIENT_ID"].presence || credential(:client_id)
    end

    def client_secret(configuration: nil)
      configuration&.client_secret.presence || ENV["GOOGLE_DRIVE_CLIENT_SECRET"].presence || credential(:client_secret)
    end

    def generate_pkce
      verifier = Base64.urlsafe_encode64(SecureRandom.random_bytes(64), padding: false)
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      { verifier:, challenge: }
    end

    def authorization_url(redirect_uri:, state:, code_challenge:, configuration: nil)
      ensure_configured!(configuration: configuration)
      query = URI.encode_www_form(
        client_id: client_id(configuration: configuration),
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: SCOPES.join(" "),
        access_type: "offline",
        include_granted_scopes: "true",
        prompt: "consent",
        state: state,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      )
      "#{AUTHORIZE_URL}?#{query}"
    end

    def exchange_code(code:, redirect_uri:, code_verifier:, configuration: nil)
      token_request(
        code: code,
        client_id: client_id(configuration: configuration),
        client_secret: client_secret(configuration: configuration),
        redirect_uri: redirect_uri,
        code_verifier: code_verifier,
        grant_type: "authorization_code",
        configuration: configuration
      )
    end

    def refresh_tokens(refresh_token:, configuration: nil)
      token_request(
        refresh_token: refresh_token,
        client_id: client_id(configuration: configuration),
        client_secret: client_secret(configuration: configuration),
        grant_type: "refresh_token",
        configuration: configuration
      )
    end

    def user_info(access_token:)
      response = request(
        Net::HTTP::Get.new(URI(USER_INFO_URL), { "Authorization" => "Bearer #{access_token}", "Accept" => "application/json" })
      )
      parse_json_response(response, authentication_request: true)
    end

    def revoke(token:)
      return if token.blank?

      uri = URI(REVOKE_URL)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(token: token)
      response = self.request(request)
      return true if response.is_a?(Net::HTTPSuccess)

      raise ApiError, "Google token revocation failed (HTTP #{response.code})"
    end

    private
      def credential(key)
        credentials = Rails.application.credentials
        return unless credentials.respond_to?(:dig)

        credentials.dig(:google_drive, key)
      end

      def ensure_configured!(configuration: nil)
        raise ConfigurationError, "Google Drive OAuth is not configured" unless configured?(configuration: configuration)
      end

      def token_request(params)
        configuration = params.delete(:configuration)
        ensure_configured!(configuration: configuration)
        uri = URI(TOKEN_URL)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(params)
        parse_json_response(self.request(request), authentication_request: true)
      end

      def request(request)
        ExternalAccess.require!(:google_drive)
        uri = request.uri
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: true,
          open_timeout: REQUEST_TIMEOUT,
          read_timeout: REQUEST_TIMEOUT,
          write_timeout: REQUEST_TIMEOUT
        ) { |http| http.request(request) }
      rescue Net::OpenTimeout,
             Net::ReadTimeout,
             Net::WriteTimeout,
             OpenSSL::SSL::SSLError,
             EOFError,
             Errno::ECONNRESET,
             Errno::ETIMEDOUT,
             SocketError => e
        raise TransientError, "Google request failed: #{e.class}"
      end

      def parse_json_response(response, authentication_request: false)
        payload = JSON.parse(response.body.presence || "{}")
        return payload if response.is_a?(Net::HTTPSuccess)

        message = payload.dig("error", "message") || payload["error_description"] || payload["error"] || "Google request failed"
        reasons = Array(payload.dig("error", "errors")).filter_map { |error| error["reason"] }
        transient_status = response.code.to_i.in?([ 408, 429 ]) || response.code.to_i >= 500
        rate_limited = response.code.to_i == 429 || reasons.any? do |reason|
          reason.in?(%w[rateLimitExceeded userRateLimitExceeded sharingRateLimitExceeded])
        end
        error_class = if rate_limited || transient_status
          TransientError
        elsif authentication_request || response.code.to_i == 401
          AuthenticationError
        elsif response.code.to_i == 403
          PermissionError
        elsif response.code.to_i == 404
          FileMissingError
        else
          ApiError
        end
        raise error_class, "#{message.to_s.truncate(300)} (HTTP #{response.code})"
      rescue JSON::ParserError
        raise(response.code.to_i >= 500 ? TransientError : ApiError, "Google returned an invalid response (HTTP #{response.code})")
      end
  end

  def initialize(connection)
    @connection = connection
  end

  def find_file(schedule_id:, logical_key:)
    query = [
      "trashed = false",
      "appProperties has { key='sure_schedule_id' and value='#{schedule_id}' }",
      "appProperties has { key='sure_logical_key' and value='#{logical_key}' }"
    ].join(" and ")
    payload = authorized_json(
      :get,
      "#{DRIVE_API_URL}/files",
      params: { q: query, spaces: "drive", fields: "files(id,name,webViewLink,trashed)", pageSize: 2 }
    )
    payload.fetch("files", []).first
  end

  def create_file(name:, content:, schedule_id:, logical_key:)
    boundary = "sure_#{SecureRandom.hex(16)}"
    metadata = {
      name: name,
      mimeType: "text/csv",
      appProperties: {
        sure_schedule_id: schedule_id.to_s,
        sure_logical_key: logical_key.to_s
      }
    }
    body = [
      "--#{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n#{metadata.to_json}\r\n",
      "--#{boundary}\r\nContent-Type: text/csv; charset=UTF-8\r\n\r\n#{content}\r\n",
      "--#{boundary}--\r\n"
    ].join

    authorized_json(
      :post,
      "#{DRIVE_UPLOAD_URL}/files",
      params: { uploadType: "multipart", fields: "id,name,webViewLink,trashed" },
      body: body,
      content_type: "multipart/related; boundary=#{boundary}"
    )
  end

  def update_file(file_id:, name:, content:)
    boundary = "sure_#{SecureRandom.hex(16)}"
    metadata = { name: name }
    body = [
      "--#{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n#{metadata.to_json}\r\n",
      "--#{boundary}\r\nContent-Type: text/csv; charset=UTF-8\r\n\r\n#{content}\r\n",
      "--#{boundary}--\r\n"
    ].join

    authorized_json(
      :patch,
      "#{DRIVE_UPLOAD_URL}/files/#{escape_path(file_id)}",
      params: { uploadType: "multipart", fields: "id,name,webViewLink,trashed" },
      body: body,
      content_type: "multipart/related; boundary=#{boundary}"
    )
  end

  def get_file(file_id:)
    authorized_json(
      :get,
      "#{DRIVE_API_URL}/files/#{escape_path(file_id)}",
      params: { fields: "id,name,webViewLink,trashed" }
    )
  end

  private
    attr_reader :connection

    def authorized_json(method, url, params: {}, body: nil, content_type: nil, retry_auth: true)
      uri = URI(url)
      uri.query = URI.encode_www_form(params) if params.present?
      request_class = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method)
      request = request_class.new(uri)
      request["Authorization"] = "Bearer #{connection.access_token!}"
      request["Accept"] = "application/json"
      request["Content-Type"] = content_type if content_type
      request.body = body if body

      response = self.class.send(:request, request)
      if response.code.to_i == 401 && retry_auth
        connection.access_token!(force_refresh: true)
        return authorized_json(method, url, params: params, body: body, content_type: content_type, retry_auth: false)
      end

      self.class.send(:parse_json_response, response)
    end

    def escape_path(value)
      URI.encode_www_form_component(value.to_s)
    end
end
