# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Logos', type: :request do
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
      scopes: %w[read],
      source: 'web'
    )
  end

  let(:'X-Api-Key') { api_key.plain_key }
  let(:id) { SecureRandom.uuid }

  path '/api/v1/accounts/{id}/logo' do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true, description: 'Account ID'

    get 'Download a stored account logo' do
      tags 'Logos'
      description 'Streams the custom bank logo (128 px WebP) or the stored provider logo of an accessible account. ' \
                  'External logo URLs are not proxied; clients load those directly.'
      security [ { apiKeyAuth: [] } ]
      produces 'image/webp', 'image/png', 'image/jpeg', 'application/json'

      response '404', 'account not accessible or without a stored logo' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { 'invalid-key' }

        run_test!
      end
    end
  end

  path '/api/v1/merchants/{id}/logo' do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true, description: 'Merchant ID'

    get 'Download a custom merchant logo' do
      tags 'Logos'
      description "Streams the family's custom logo for a merchant as a 128 px WebP image."
      security [ { apiKeyAuth: [] } ]
      produces 'image/webp', 'application/json'

      response '404', 'merchant without a custom logo for this family' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { 'invalid-key' }

        run_test!
      end
    end
  end

  path '/api/v1/users/{id}/avatar' do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true, description: 'Family member ID'

    get "Download a family member's profile picture" do
      tags 'Logos'
      description "Streams a member's profile picture as a small WebP image, e.g. to show who made a transfer into a shared account."
      security [ { apiKeyAuth: [] } ]
      produces 'image/webp', 'application/json'

      response '404', 'member outside the family or without a profile picture' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { 'invalid-key' }

        run_test!
      end
    end
  end
end
