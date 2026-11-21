class AddMcpCustomInstructionsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :mcp_custom_instructions, :text
  end
end
