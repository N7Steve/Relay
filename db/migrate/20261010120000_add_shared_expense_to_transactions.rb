class AddSharedExpenseToTransactions < ActiveRecord::Migration[8.1]
  def up
    add_column :transactions, :shared_expense, :boolean, default: false, null: false unless column_exists?(:transactions, :shared_expense)

    # Classify history in every family, including currently excluded entries.
    # Never rewrite tags or financial fields and never run application callbacks.
    execute <<~SQL
      UPDATE transactions SET shared_expense = true
      WHERE shared_expense = false AND id IN (
        SELECT taggings.taggable_id
        FROM taggings
        INNER JOIN tags ON tags.id = taggings.tag_id
        INNER JOIN entries ON entries.entryable_id = taggings.taggable_id AND entries.entryable_type = 'Transaction'
        INNER JOIN accounts ON accounts.id = entries.account_id AND accounts.family_id = tags.family_id
        WHERE taggings.taggable_type = 'Transaction' AND tags.name = 'Gastos compartidos'
      )
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Native shared expenses cannot be represented by the historical tags without changing them"
  end
end
