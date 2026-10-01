class CreateGoogleDriveOauthConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :google_drive_oauth_configurations, id: :uuid do |t|
      t.references :family, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, type: :uuid, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :client_id, null: false
      t.text :client_secret, null: false

      t.timestamps
    end
  end
end
