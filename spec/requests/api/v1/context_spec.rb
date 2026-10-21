# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Context', type: :request do
  let(:user) { users(:family_member) }
  let(:api_key) do
    ApiKey.create!(user: user, name: 'API Docs Key', key: ApiKey.generate_secure_key, scopes: %w[read], source: 'web')
  end
  let(:'X-Api-Key') { api_key.plain_key }

  path '/api/v1/context' do
    get 'Read the authenticated identity and effective capability contract' do
      tags 'Context'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      description 'No secrets are returned. A write token never expands account permissions. MCP availability reflects instance configuration. Responses are private and not cacheable.'

      response '200', 'identity and capabilities' do
        schema '$ref' => '#/components/schemas/ApiContext'
        run_test!
      end

      response '401', 'missing or revoked credential' do
        let(:'X-Api-Key') { nil }
        schema '$ref' => '#/components/schemas/ErrorResponse'
        run_test!
      end
    end
  end
end
