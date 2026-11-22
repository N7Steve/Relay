# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Android Updates', type: :request do
  let(:family) do
    Family.create!(
      name: 'API Family',
      currency: 'USD',
      locale: 'en',
      date_format: '%m-%d-%Y'
    )
  end

  let(:user) do
    family.users.create!(
      email: 'api-user@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(
      user: user,
      name: 'API Docs Key',
      key: key,
      scopes: %w[read_write],
      source: 'web'
    )
  end

  let(:'X-Api-Key') { api_key.plain_key }

  path '/api/v1/android/updates/latest' do
    get 'Show the bundled Android release' do
      tags 'Android Updates'
      description 'Returns the signed Android build bundled with this server image, or enabled false when none is bundled.'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'Android update channel returned' do
        schema '$ref' => '#/components/schemas/AndroidUpdate'

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { 'invalid-key' }

        run_test!
      end
    end
  end

  path '/api/v1/android/updates/{version_code}/apk' do
    parameter name: :version_code, in: :path, type: :integer, required: true, description: 'Version code from the latest release'

    get 'Download the bundled Android APK' do
      tags 'Android Updates'
      description 'Streams the APK described by the latest release. Clients must verify size, SHA-256 and signing certificate.'
      security [ { apiKeyAuth: [] } ]
      produces 'application/vnd.android.package-archive', 'application/json'

      response '404', 'no bundled release with this version code' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:version_code) { 1 }

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:version_code) { 1 }
        let(:'X-Api-Key') { 'invalid-key' }

        run_test!
      end
    end
  end
end
