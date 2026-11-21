class AddSharedExpenseToScheduledPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :scheduled_payments, :shared_expense, :boolean, default: false, null: false
  end
end
