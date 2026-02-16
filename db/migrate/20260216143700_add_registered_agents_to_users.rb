class AddRegisteredAgentsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :registered_agents, :jsonb, default: [], null: false
    add_column :tasks, :pending_agent_registration, :boolean, default: false, null: false
    add_index :tasks, :pending_agent_registration
  end
end
