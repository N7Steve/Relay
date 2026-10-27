# frozen_string_literal: true

require 'swagger_helper'

# Transaction posting_status is retired; schemas come from the shared MCP catalog.

RSpec.describe 'API V1 Daily Operations', type: :request do
  let(:user) { users(:family_admin) }
  let(:api_key) do
    ApiKey.create!(user: user, name: 'API Docs Key', key: ApiKey.generate_secure_key, scopes: %w[read_write], source: 'web')
  end
  let(:'X-Api-Key') { api_key.plain_key }
  let(:payload) { { arguments: {} } }

  Mcp::Catalog.all.each_value do |tool|
    path "/api/v1/actions/#{tool[:name]}" do
      post tool[:description] do
        tags 'Daily operations'
        consumes 'application/json'
        produces 'application/json'
        security [ { apiKeyAuth: [] } ]
        description 'Shared operation with MCP. Money uses signed decimal strings. Writes require a unique actor-scoped idempotency_key; reusing a key with changed arguments returns 422. Account permissions are checked on every call. Family-wide organization writes require administrator and complete account visibility.'
        parameter name: :payload, in: :body, required: true, schema: {
          type: :object, required: [ 'arguments' ], additionalProperties: false,
          properties: { arguments: { '$ref' => "#/components/schemas/DailyInput#{tool[:name].camelize}" } }
        }
        response '200', 'operation result' do
          schema '$ref' => '#/components/schemas/DailyOperationResult'
          run_test!
        end
        response '401', 'missing, expired or revoked credential' do
          schema '$ref' => '#/components/schemas/ErrorResponse'
          run_test!
        end
        response '403', 'credential scope or account permission denied' do
          schema '$ref' => '#/components/schemas/ErrorResponse'
          run_test!
        end
        response '404', 'resource unavailable to this actor' do
          schema '$ref' => '#/components/schemas/ErrorResponse'
          run_test!
        end
        response '422', 'invalid input or idempotency conflict' do
          schema '$ref' => '#/components/schemas/ErrorResponse'
          run_test!
        end
      end
    end
  end
end
