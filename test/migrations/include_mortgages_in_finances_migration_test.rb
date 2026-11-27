# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261128120000_include_mortgages_in_finances")

# Mortgages placed outside the finances boundary to keep them out of net worth
# move back in: the subtype now does that. Their transfers must end up as
# Transfer.outflow_kind_for / inflow_kind_for classify them for an included
# mortgage, i.e. the instalment is a loan payment.
class IncludeMortgagesInFinancesMigrationTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @checking = @family.accounts.create!(name: "Nómina", balance: 5_000, currency: "EUR", accountable: Depository.new)
  end

  test "a mortgage outside the finances comes back in with its instalments as loan payments" do
    mortgage = outside_finances(Loan.new(subtype: "mortgage"))
    transfer = create_transfer(from_account: @checking, to_account: mortgage, amount: 543.56, currency: "EUR")
    mark_crossing(transfer, "transfer_to_excluded")

    run_migration

    mortgage.reload
    assert_equal "included", mortgage.financial_treatment
    assert_not mortgage.cashflow_boundary?
    assert_not mortgage.exclude_from_reports?
    assert_equal Transfer.outflow_kind_for(@checking, mortgage), transfer.outflow_transaction.reload.kind
    assert_equal "loan_payment", transfer.outflow_transaction.kind
    assert_equal Transfer.inflow_kind_for(@checking, mortgage), transfer.inflow_transaction.reload.kind
  end

  test "money drawn from the mortgage is classified by where it went" do
    mortgage = outside_finances(Loan.new(subtype: "mortgage"))
    transfer = create_transfer(from_account: mortgage, to_account: @checking, amount: 1_000, currency: "EUR")
    mark_crossing(transfer, "transfer_from_excluded")

    run_migration

    assert_equal "funds_movement", transfer.outflow_transaction.reload.kind
    assert_equal "funds_movement", transfer.inflow_transaction.reload.kind
  end

  test "other accounts outside the finances keep their treatment" do
    shared = outside_finances(Depository.new)
    car_loan = outside_finances(Loan.new(subtype: "auto"))
    transfer = create_transfer(from_account: @checking, to_account: shared, amount: 100, currency: "EUR")
    mark_crossing(transfer, "transfer_to_excluded")

    run_migration

    assert shared.reload.cashflow_boundary?
    assert car_loan.reload.cashflow_boundary?
    assert_equal "transfer_to_excluded", transfer.outflow_transaction.reload.kind
  end

  private
    def outside_finances(accountable)
      account = @family.accounts.create!(name: "Cuenta", balance: 100_000, currency: "EUR", accountable: accountable)
      # As the account was stored before mortgages were kept in the finances.
      account.update_columns(cashflow_boundary: true, exclude_from_reports: true, financial_treatment: "outside_finances")
      account
    end

    def mark_crossing(transfer, kind)
      transfer.outflow_transaction.update_columns(kind: kind)
      transfer.inflow_transaction.update_columns(kind: kind)
    end

    def run_migration
      ActiveRecord::Migration.suppress_messages { IncludeMortgagesInFinances.new.migrate(:up) }
    end
end
