# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 File transfer', type: :request do
  let(:user) { users(:family_admin) }
  let(:api_key) { ApiKey.create!(user: user, name: 'Files docs', key: ApiKey.generate_secure_key, scopes: %w[read_write], source: 'web') }
  let(:'X-Api-Key') { api_key.plain_key }

  path '/api/v1/files' do
    post 'Stage an actor-bound original file' do
      tags 'File transfer'
      consumes 'multipart/form-data'
      produces 'application/json'
      security [ { apiKeyAuth: [] } ]
      description 'Maximum 100 MiB. SHA-256 and an actor-scoped upload key are required. Token expires one hour after first upload; an identical retry does not extend it. Unattached staging is cleaned after two hours. MCP credentials use /mcp/files instead.'
      parameter name: :payload, in: :body, required: true, schema: { '$ref' => '#/components/schemas/FileUploadRequest' }
      response '201', 'staged file token and checksum' do
        schema '$ref' => '#/components/schemas/FileUploadResult'
        run_test!
      end
      response('401', 'credential required') { run_test! }
      response('403', 'write scope required') { run_test! }
      response('422', 'invalid file, checksum or collision') { run_test! }
    end
  end

  path '/api/v1/files/download' do
    get 'Download an authorized original without a public storage redirect' do
      tags 'File transfer'
      produces 'application/octet-stream'
      security [ { apiKeyAuth: [] } ]
      parameter name: :kind, in: :query, required: true, schema: { type: :string, enum: %w[statement document attachment backup import] }
      parameter name: :id, in: :query, required: true, schema: { type: :string, format: :uuid }
      parameter name: :attachment_id, in: :query, required: false, schema: { type: :string, format: :uuid }
      response '200', 'original bytes; authorization rechecked on each request' do
        schema type: :string, format: :binary
        run_test!
      end
      response('401', 'credential required') { run_test! }
      response('403', 'resource permission denied') { run_test! }
      response('404', 'original unavailable') { run_test! }
      response('422', 'backup not ready or historical original missing') { run_test! }
    end
  end
end
