# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Family Sync', type: :request do
  let(:user) { users(:family_admin) }
  let(:api_key) do
    ApiKey.create!(user: user, name: 'API Docs Key', key: ApiKey.generate_secure_key, scopes: %w[read_write], source: 'web')
  end
  let(:'X-Api-Key') { api_key.plain_key }

  path '/api/v1/sync' do
    post 'Queue a family synchronization' do
      tags 'Syncs'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      description 'Requires a family administrator with write scope. Reuses the existing sync job, rules and ExternalAccess policy; it does not acquire external market data. Poll the sync history endpoints for completion.'

      response '202', 'family synchronization queued' do
        schema '$ref' => '#/components/schemas/SyncQueued'
        run_test!
      end

      response '401', 'unauthorized' do
        let(:'X-Api-Key') { nil }
        schema '$ref' => '#/components/schemas/ErrorResponse'
        run_test!
      end

      response '403', 'family administrator required' do
        let(:user) { users(:family_member) }
        schema '$ref' => '#/components/schemas/ErrorResponse'
        run_test!
      end
    end
  end
end
