class BindOauthTokensToMcpResource < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_access_grants, :code_challenge, :string
    add_column :oauth_access_grants, :code_challenge_method, :string
    add_column :oauth_access_grants, :mcp_resource, :string
    add_column :oauth_access_tokens, :mcp_resource, :string
    create_table :api_operations, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :key, null: false
      t.string :request_digest, null: false
      t.jsonb :result, null: false, default: {}
      t.timestamps
    end
    add_index :api_operations, [ :user_id, :key ], unique: true
  end
end
