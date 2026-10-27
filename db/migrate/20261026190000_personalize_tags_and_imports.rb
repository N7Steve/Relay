class PersonalizeTagsAndImports < ActiveRecord::Migration[8.1]
  def up
    add_reference :tags, :user, type: :uuid, foreign_key: true
    add_reference :imports, :user, type: :uuid, foreign_key: true
    add_column :imports, :actor_bound, :boolean, default: false, null: false
    execute <<~SQL
      UPDATE tags SET user_id = (
        SELECT users.id FROM users WHERE users.family_id = tags.family_id
        ORDER BY CASE WHEN users.role IN ('admin', 'super_admin') THEN 0 ELSE 1 END,
                 users.created_at, users.id LIMIT 1
      )
    SQL
    remove_index :tags, name: :index_tags_on_family_id_and_name
    add_index :tags, [ :family_id, :user_id, :name ], unique: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Personal tag names may overlap between users"
  end
end
