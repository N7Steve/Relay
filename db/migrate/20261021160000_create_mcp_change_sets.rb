class CreateMcpChangeSets < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_change_sets, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :family, null: false, type: :uuid, foreign_key: true
      t.jsonb :authority, null: false, default: {}
      t.string :credential_name, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :operations, null: false, default: []
      t.datetime :approved_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :mcp_change_sets, [ :user_id, :status, :created_at ]
  end
end
