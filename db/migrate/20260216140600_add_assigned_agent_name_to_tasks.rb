class AddAssignedAgentNameToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :assigned_agent_name, :string, null: true
    add_index :tasks, :assigned_agent_name
  end
end
