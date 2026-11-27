# The Agenda series that pays a loan's instalment, owned by the loan: its
# amount comes from the loan's schedule and only the loan's own flows write
# to the loan account.
class AddLoanToScheduledPayments < ActiveRecord::Migration[8.1]
  def change
    add_reference :scheduled_payments, :loan, type: :uuid, foreign_key: { on_delete: :nullify }, index: { unique: true }
  end
end
