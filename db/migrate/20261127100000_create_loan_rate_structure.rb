# Structured interest terms for loans whose rate is built from parts: a fixed
# or index-linked rate period, a spread, bonuses that discount it, and the
# revisions that froze each combination on the date it took effect.
#
# Additive only. A loan without rate periods keeps reading `interest_rate` and
# `variable_rate_schedule` exactly as before.
class CreateLoanRateStructure < ActiveRecord::Migration[8.1]
  def change
    change_table :loans, bulk: true do |t|
      t.string :interest_accrual, null: false, default: "monthly"
      t.boolean :interest_tracking, null: false, default: false
    end
    add_check_constraint :loans, "interest_accrual IN ('monthly', 'daily')", name: "chk_loans_interest_accrual"

    create_table :loan_rate_periods, id: :uuid do |t|
      t.references :loan, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.date :starts_on, null: false
      t.string :rate_kind, null: false
      t.decimal :base_rate, precision: 10, scale: 4
      t.string :reference_index
      t.decimal :spread, precision: 10, scale: 4
      t.integer :review_interval_months, null: false, default: 12
      t.decimal :floor_rate, precision: 10, scale: 4, null: false, default: 0
      t.string :lender_name
      t.boolean :applies_bonuses, null: false, default: true
      t.timestamps
    end
    add_index :loan_rate_periods, %i[loan_id starts_on], unique: true
    add_check_constraint :loan_rate_periods, "rate_kind IN ('fixed', 'variable')", name: "chk_loan_rate_periods_kind"
    add_check_constraint :loan_rate_periods,
      "(rate_kind = 'fixed' AND base_rate IS NOT NULL) OR (rate_kind = 'variable' AND reference_index IS NOT NULL AND spread IS NOT NULL)",
      name: "chk_loan_rate_periods_terms"
    add_check_constraint :loan_rate_periods, "review_interval_months BETWEEN 1 AND 120", name: "chk_loan_rate_periods_interval"

    create_table :loan_rate_bonuses, id: :uuid do |t|
      t.references :loan, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :name, null: false
      t.string :kind, null: false, default: "other"
      t.decimal :points, precision: 6, scale: 4, null: false
      t.boolean :active, null: false, default: true
      t.decimal :annual_cost, precision: 19, scale: 4
      t.timestamps
    end
    add_check_constraint :loan_rate_bonuses, "points >= 0", name: "chk_loan_rate_bonuses_points"
    add_check_constraint :loan_rate_bonuses, "annual_cost IS NULL OR annual_cost >= 0", name: "chk_loan_rate_bonuses_cost"

    create_table :loan_rate_revisions, id: :uuid do |t|
      t.references :loan, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.date :effective_on, null: false
      t.decimal :rate, precision: 10, scale: 4, null: false
      t.string :rate_kind, null: false
      t.decimal :base_rate, precision: 10, scale: 4
      t.string :reference_index
      t.date :index_month
      t.decimal :index_value, precision: 10, scale: 5
      t.decimal :spread, precision: 10, scale: 4
      t.decimal :bonus_points, precision: 6, scale: 4, null: false, default: 0
      t.string :status, null: false, default: "calculated"
      t.timestamps
    end
    add_index :loan_rate_revisions, %i[loan_id effective_on], unique: true
    add_check_constraint :loan_rate_revisions, "status IN ('calculated', 'confirmed')", name: "chk_loan_rate_revisions_status"
    add_check_constraint :loan_rate_revisions, "rate >= 0", name: "chk_loan_rate_revisions_rate"

    # An extra repayment and what the borrower asked the lender to do with it:
    # keep the term and lower the instalment, or keep the instalment and end
    # sooner. The money itself is an ordinary entry on the loan account.
    create_table :loan_prepayments, id: :uuid do |t|
      t.references :loan, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.date :paid_on, null: false
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :mode, null: false
      t.decimal :fee, precision: 19, scale: 4, null: false, default: 0
      t.references :entry, foreign_key: { on_delete: :nullify }, type: :uuid
      t.text :notes
      t.timestamps
    end
    add_check_constraint :loan_prepayments, "amount > 0", name: "chk_loan_prepayments_amount"
    add_check_constraint :loan_prepayments, "fee >= 0", name: "chk_loan_prepayments_fee"
    add_check_constraint :loan_prepayments, "mode IN ('reduce_payment', 'reduce_term')", name: "chk_loan_prepayments_mode"

    create_table :reference_rates, id: :uuid do |t|
      t.string :index_key, null: false
      t.date :month, null: false
      t.decimal :value, precision: 10, scale: 5, null: false
      t.string :source, null: false
      t.timestamps
    end
    add_index :reference_rates, %i[index_key month], unique: true
  end
end
