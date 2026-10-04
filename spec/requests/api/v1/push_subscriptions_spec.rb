# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API V1 Push Subscriptions", type: :request do
  let(:family) { Family.create!(name: "API Family") }
  let(:user) do
    family.users.create!(email: "push-api@example.com", password: "password123", ai_enabled: true)
  end
  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(user: user, name: "API Docs Key", key: key, scopes: %w[read_write], source: "web")
  end
  let(:"X-Api-Key") { api_key.plain_key }

  path "/api/v1/push_subscriptions" do
    post "Register an APNs device token" do
      description "Unavailable in Relay's self-hosted installation. Legacy Apple credentials do not enable push registration."
      tags "Push Subscriptions"
      security [ { apiKeyAuth: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :subscription, in: :body, required: true, schema: { "$ref" => "#/components/schemas/PushSubscriptionRegistration" }
      let(:subscription) { { token: "ab" * 32, environment: "sandbox", platform: "ios" } }

      response "403", "push unavailable in Relay" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end
    end
  end

  path "/api/v1/push_subscriptions/{id}" do
    parameter name: :id, in: :path, type: :string, required: true
    let(:subscription) do
      user.push_subscriptions.create!(
        token: "cd" * 32,
        environment: "sandbox",
        platform: "ios",
        last_registered_at: Time.current
      )
    end
    let(:id) { subscription.id }

    delete "Unregister an APNs device token" do
      description "Unavailable in Relay's self-hosted installation. Historical device tokens remain stored."
      tags "Push Subscriptions"
      security [ { apiKeyAuth: [] } ]

      response "403", "push unavailable in Relay" do
        produces "application/json"
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end
    end
  end
end
