class AddEnableTransferMatcherToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :enable_transfer_matcher, :boolean, default: true, null: false
  end
end
