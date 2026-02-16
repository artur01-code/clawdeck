class CreateAgentsAndSubtasks < ActiveRecord::Migration[8.0]
  def change
    # Agents table
    create_table :agents do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :is_dev, default: false, null: false
      t.string :role_type # PO, UX, DEV, QA, DEVOPS, ANALYST
      t.string :emoji
      t.timestamps
    end
    add_index :agents, [:user_id, :name], unique: true

    # Extend tasks for multi-agent workflow
    add_column :tasks, :ticket_id, :string
    add_column :tasks, :is_development_ticket, :boolean, default: false, null: false
    add_column :tasks, :required_agents, :jsonb, default: []
    add_column :tasks, :workflow_mode, :string, default: "single" # single | multi_agent
    add_column :tasks, :orchestration_state, :jsonb, default: {
      subtasks_created: false,
      current_subtask_index: 0,
      blocked_reason: nil
    }
    add_index :tasks, :ticket_id
    add_index :tasks, :workflow_mode

    # SubTasks table
    create_table :subtasks do |t|
      t.string :subtask_id, null: false
      t.references :task, null: false, foreign_key: true # parent task
      t.references :user, null: false, foreign_key: true
      t.string :assigned_agent_name, null: false
      t.string :role # PO, UX, DEV, QA derived from agent
      t.integer :status, default: 0, null: false # queued=0, up_next=1, in_progress=2, needs_review=3, done=4, blocked=5
      t.jsonb :depends_on_subtask_ids, default: []
      t.jsonb :artifact_targets, default: []
      t.boolean :pending_agent_registration, default: false, null: false
      t.string :blocked_reason
      t.text :notes
      t.timestamps
    end
    add_index :subtasks, :subtask_id, unique: true
    add_index :subtasks, :assigned_agent_name
    add_index :subtasks, :status
    add_index :subtasks, :pending_agent_registration
  end
end
