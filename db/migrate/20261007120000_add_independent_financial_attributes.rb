# Additive stage only. Historical values remain NULL until inventoried/backfilled;
# compatibility readers preserve their meaning without rewriting source metadata.
class AddIndependentFinancialAttributes < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :import_protected, :boolean
    add_column :investments, :tax_treatment, :string
    add_column :investments, :tracking_mode, :string
    add_column :accounts, :financial_treatment, :string
    add_column :transactions, :posting_status, :string
  end
end
