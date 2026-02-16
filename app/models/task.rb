class Task < ApplicationRecord
  belongs_to :user
  belongs_to :board
  has_many :activities, class_name: "TaskActivity", dependent: :destroy
  has_many :subtasks, dependent: :destroy

  enum :priority, { none: 0, low: 1, medium: 2, high: 3 }, default: :none, prefix: true
  enum :status, { inbox: 0, up_next: 1, in_progress: 2, in_review: 3, done: 4 }, default: :inbox

  validates :name, presence: true
  validates :priority, inclusion: { in: priorities.keys }
  validates :status, inclusion: { in: statuses.keys }

  # Activity tracking - must be declared before callbacks that use it
  attr_accessor :activity_source, :actor_name, :actor_emoji, :activity_note

  # Store activity_source before commit so it survives the transaction
  before_save :store_activity_source_for_broadcast

  # Real-time broadcasts to user's board (only for API/background changes)
  # Skip broadcasts when activity_source is "web" since the UI already handles it
  after_create_commit :broadcast_create
  after_update_commit :broadcast_update
  after_destroy_commit :broadcast_destroy
  after_create :record_creation_activity
  after_create :create_subtasks_if_multi_agent
  after_update :record_update_activities

  # Position management - acts_as_list functionality without the gem
  before_create :set_position
  before_save :sync_completed_with_status
  before_update :track_completion_time, if: :will_save_change_to_status?

  # Order incomplete tasks by position, completed tasks by completion time (most recent first)
  scope :incomplete, -> { where(completed: false).reorder(position: :asc) }
  scope :completed, -> { where(completed: true).reorder(completed_at: :desc) }
  scope :assigned_to_agent, ->(agent_name = nil) { 
    query = where(assigned_to_agent: true).reorder(assigned_at: :asc)
    agent_name.present? ? query.where(assigned_agent_name: agent_name) : query
  }
  scope :unassigned, -> { where(assigned_to_agent: false) }
  default_scope { order(completed: :asc, position: :asc) }

  # Agent assignment methods
  def assign_to_agent!(agent_name = nil)
    update!(assigned_to_agent: true, assigned_at: Time.current, assigned_agent_name: agent_name)
    check_agent_registration! if agent_name.present?
  end

  def unassign_from_agent!
    update!(assigned_to_agent: false, assigned_at: nil, assigned_agent_name: nil, pending_agent_registration: false)
  end

  # Check if assigned agent is registered, if not create spawn task
  def check_agent_registration!
    return if assigned_agent_name.blank?
    return if user.agent_registered?(assigned_agent_name)
    
    # Mark this task as pending agent registration
    update_column(:pending_agent_registration, true)
    
    # Create spawn task for manager agent
    manager = user.manager_agent_name
    spawn_task = user.tasks.create!(
      name: "🔧 Spawn sub-agent: #{assigned_agent_name}",
      description: "Create and start a new sub-agent with name '#{assigned_agent_name}' to handle assigned tasks.\n\nOnce spawned, the agent should poll with:\n`GET /tasks?assigned=true&agent=#{assigned_agent_name}`",
      board: board,
      status: :up_next,
      priority: :high,
      assigned_to_agent: true,
      assigned_agent_name: manager,
      assigned_at: Time.current,
      activity_source: "system"
    )
    
    # Auto-register manager if first time
    user.register_agent(manager) unless user.agent_registered?(manager)
  end

  private

  def set_position
    return if position.present?

    # Append: set position to end of list
    max_position = board.tasks.where(status: status).maximum(:position) || 0
    self.position = max_position + 1
  end

  def store_activity_source_for_broadcast
    @stored_activity_source = activity_source
  end

  def skip_broadcast?
    @stored_activity_source == "web" || activity_source == "web"
  end

  def sync_completed_with_status
    self.completed = (status == "done")
  end

  def track_completion_time
    if status == "done"
      self.completed_at = Time.current
    else
      self.completed_at = nil
    end
  end

  def record_creation_activity
    TaskActivity.record_creation(self, source: activity_source || "web", actor_name: actor_name, actor_emoji: actor_emoji, note: activity_note)
  end

  def record_update_activities
    source = activity_source || "web"

    # Track status/column changes
    if saved_change_to_status?
      old_status, new_status = saved_change_to_status
      TaskActivity.record_status_change(self, old_status: old_status, new_status: new_status, source: source, actor_name: actor_name, actor_emoji: actor_emoji, note: activity_note)
    end

    # Track field changes
    tracked_changes = saved_changes.slice(*TaskActivity::TRACKED_FIELDS)
    TaskActivity.record_changes(self, tracked_changes, source: source, actor_name: actor_name, actor_emoji: actor_emoji, note: activity_note) if tracked_changes.any?
  end

  # Turbo Streams broadcasts for real-time updates
  def broadcast_create
    return if skip_broadcast?

    broadcast_to_board(
      action: :prepend,
      target: "column-#{status}",
      partial: "boards/task_card",
      locals: { task: self }
    )
    broadcast_column_count(status)
  end

  def broadcast_update
    return if skip_broadcast?

    # If status changed, handle move between columns
    if saved_change_to_status?
      old_status, new_status = saved_change_to_status
      # Remove from old column
      broadcast_to_board(action: :remove, target: "task_#{id}")
      # Add to new column
      broadcast_to_board(
        action: :prepend,
        target: "column-#{new_status}",
        partial: "boards/task_card",
        locals: { task: self }
      )
      broadcast_column_count(old_status)
      broadcast_column_count(new_status)
    else
      # Just update the card in place
      broadcast_to_board(
        action: :replace,
        target: "task_#{id}",
        partial: "boards/task_card",
        locals: { task: self }
      )
    end
  end

  def broadcast_destroy
    return if skip_broadcast?

    # Cache values before they become inaccessible
    cached_board_id = board_id
    cached_status = status
    cached_id = id
    stream = "board_#{cached_board_id}"

    Turbo::StreamsChannel.broadcast_action_to(stream, action: :remove, target: "task_#{cached_id}")

    # Update column count
    count = Board.find(cached_board_id).tasks.where(status: cached_status).count
    Turbo::StreamsChannel.broadcast_action_to(
      stream,
      action: :replace,
      target: "column-#{cached_status}-count",
      html: %(<span id="column-#{cached_status}-count" class="ml-auto text-xs text-content-secondary bg-bg-elevated px-1.5 py-0.5 rounded">#{count}</span>)
    )
  end

  def broadcast_column_count(column_status)
    count = board.tasks.where(status: column_status).count
    broadcast_to_board(
      action: :replace,
      target: "column-#{column_status}-count",
      html: %(<span id="column-#{column_status}-count" class="ml-auto text-xs text-content-secondary bg-bg-elevated px-1.5 py-0.5 rounded">#{count}</span>)
    )
  end

  def board_stream_name
    "board_#{board_id}"
  end

  def broadcast_to_board(action:, target:, **options)
    Turbo::StreamsChannel.broadcast_action_to(board_stream_name, action: action, target: target, **options)
  end
  
  # Multi-agent orchestration methods
  def multi_agent?
    workflow_mode == "multi_agent"
  end
  
  def create_subtasks!
    return if orchestration_state["subtasks_created"]
    return unless multi_agent?
    return if required_agents.blank?
    
    # Generate ticket_id if not present
    self.ticket_id ||= "TASK-#{id}"
    save!
    
    # Order agents: PO -> UX -> DEV -> QA/Others
    ordered_agents = order_agents_for_workflow(required_agents)
    
    ordered_agents.each_with_index do |agent_name, index|
      agent_record = user.agents.find_by(name: agent_name)
      role = agent_record&.role_type || infer_role_from_name(agent_name)
      
      # Set artifact targets based on role
      artifacts = case role
      when "PO" then ["BACKLOG.md"]
      when "UX" then ["DESIGN.md"]
      when "DEV" then ["IMPLEMENTATION.md"]
      when "QA" then ["QA.md"]
      else []
      end
      
      # First subtask is up_next, others are queued
      initial_status = index == 0 ? :up_next : :queued
      
      # Set dependencies (sequential chain)
      depends_on = index > 0 ? [subtasks[index - 1]&.subtask_id].compact : []
      
      subtask = subtasks.create!(
        user: user,
        assigned_agent_name: agent_name,
        role: role,
        status: initial_status,
        artifact_targets: artifacts,
        depends_on_subtask_ids: depends_on,
        pending_agent_registration: !user.agent_registered?(agent_name)
      )
      
      # Create spawn meta-task if agent not registered
      if !user.agent_registered?(agent_name)
        create_spawn_meta_task(agent_name, subtask)
      end
    end
    
    update_column(:orchestration_state, orchestration_state.merge("subtasks_created" => true))
  end
  
  def unlock_next_subtask!
    current_index = orchestration_state["current_subtask_index"] || 0
    next_subtask = subtasks.order(:created_at)[current_index + 1]
    
    if next_subtask
      next_subtask.update!(status: :up_next) if next_subtask.dependencies_met?
      update_column(:orchestration_state, orchestration_state.merge("current_subtask_index" => current_index + 1))
    else
      # All subtasks done, mark parent done
      update!(status: :done)
    end
  end
  
  def create_subtasks_if_multi_agent
    create_subtasks! if multi_agent? && required_agents.present?
  end
  
  private
  
  def order_agents_for_workflow(agents)
    return agents unless is_development_ticket
    
    # Get agent records
    agent_records = agents.map { |name| user.agents.find_by(name: name) }.compact
    
    # Order: PO first, then UX, then DEV, then QA
    ordered = []
    ordered += agent_records.select { |a| a.role_type == "PO" }.map(&:name)
    ordered += agent_records.select { |a| a.role_type == "UX" }.map(&:name)
    ordered += agent_records.select { |a| a.role_type == "DEV" }.map(&:name)
    ordered += agent_records.select { |a| a.role_type == "QA" }.map(&:name)
    ordered += (agents - ordered) # Add any remaining
    ordered
  end
  
  def infer_role_from_name(name)
    case name.downcase
    when /po|product/ then "PO"
    when /ux|design/ then "UX"
    when /dev|engineer/ then "DEV"
    when /qa|test/ then "QA"
    else "DEV"
    end
  end
  
  def create_spawn_meta_task(agent_name, subtask)
    manager_agent = user.manager_agent_name
    board.tasks.create!(
      user: user,
      name: "🔧 Spawn sub-agent: #{agent_name}",
      description: "Subtask for '#{name}' requires agent '#{agent_name}' but this agent is not registered yet.\n\nPlease spawn a new session for agent '#{agent_name}' and ensure it polls:\n\nGET /tasks?assigned=true&agent=#{agent_name}\n\nSubtask ID: #{subtask.subtask_id}",
      status: :up_next,
      priority: :high,
      assigned_to_agent: true,
      assigned_at: Time.current,
      assigned_agent_name: manager_agent,
      activity_source: "system"
    )
  end
end
