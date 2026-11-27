# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Loans', type: :request do
  let(:family) do
    Family.create!(
      name: 'API Family',
      currency: 'EUR',
      locale: 'en',
      date_format: '%d-%m-%Y'
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

  # A Spanish variable mortgage: a fixed first year, then 12-month Euribor
  # plus a spread, discounted by bonuses.
  let!(:mortgage) do
    start = Date.new(2025, 12, 12)
    ReferenceRate.create!(index_key: 'euribor_12m', month: Date.new(2026, 10, 1), value: 2.2, source: 'ecb')
    account = Account.create!(
      family: family,
      owner: user,
      name: 'Hipoteca',
      balance: 157_500,
      currency: 'EUR',
      accountable: Loan.new(
        subtype: 'mortgage',
        rate_type: 'variable',
        interest_rate: 1.5,
        term_months: 360,
        start_date: start,
        initial_balance: 157_500,
        interest_accrual: 'daily'
      )
    )
    loan = account.loan
    loan.rate_periods.create!(starts_on: start, rate_kind: 'fixed', base_rate: 2.70, review_interval_months: 12)
    loan.rate_periods.create!(starts_on: start >> 12, rate_kind: 'variable', reference_index: 'euribor_12m',
                              spread: 1.80, review_interval_months: 12)
    loan.rate_bonuses.create!(name: 'Seguro de vida', kind: 'life_insurance', points: 0.6, annual_cost: 176.13)
    loan.rate_bonuses.create!(name: 'Cuenta nómina', kind: 'payroll', points: 0.6, annual_cost: 0)
    account
  end

  let!(:checking_account) do
    Account.create!(
      family: family,
      owner: user,
      name: 'Checking Account',
      balance: 1500.50,
      currency: 'EUR',
      accountable: Depository.create!
    )
  end

  path '/api/v1/loans' do
    get 'List loans' do
      description 'Loan accounts the user can read, each with its headline figures for today: debt, original ' \
                  'principal, share repaid, rate in force, next instalment and payoff date. Read-only.'
      tags 'Loans'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'loans listed' do
        schema '$ref' => '#/components/schemas/LoanCollection'

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { 'invalid-key' }

        run_test!
      end
    end
  end

  path '/api/v1/loans/{id}' do
    parameter name: :id, in: :path, required: true, description: 'Loan account ID',
              schema: { type: :string, format: :uuid }

    get 'Retrieve a loan' do
      description 'The loan figures computed by Relay for today: the instalment due next split into principal, ' \
                  'interest and insurance; the rate in force, its composition, the next revision with its estimated ' \
                  'rate and instalment, recorded and projected revisions, rate periods and bonuses; and the full ' \
                  'amortization schedule. Loans without structured rates return empty revision lists, and loans ' \
                  'that cannot be amortised return a null schedule and instalment. Read-only.'
      tags 'Loans'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      let(:id) { mortgage.id }

      response '200', 'loan retrieved' do
        schema '$ref' => '#/components/schemas/LoanDetail'

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }

        run_test!
      end

      response '404', 'loan not found or not a loan account' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { checking_account.id }

        run_test!
      end
    end
  end
end
