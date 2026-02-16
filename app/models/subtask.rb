class Subtask < ApplicationRecord
  belongs_to :task
  belongs_to :user
  
  enum :status, {
    queued: 0,
    up_next: 1,
    in_progress: 2,
    needs_review: 3,
    done: 4,
    blocked: 5
  }, prefix: true
  
  validates :subtask_id, presence: true, uniqueness: true
  validates :assigned_agent_name, presence: true
  
  before_validation :generate_subtask_id, on: :create
  
  # Check if subtask is visible to assigned agent
  def visible_to_agent?
    !pending_agent_registration
  end
  
  # Get agent record if exists
  def agent
    user.agents.find_by(name: assigned_agent_name)
  end
  
  # Check if all dependencies are done
  def dependencies_met?
    return true if depends_on_subtask_ids.blank?
    
    depends_on_subtask_ids.all? do |dep_id|
      dep = Subtask.find_by(subtask_id: dep_id)
      dep&.status_done?
    end
  end
  
  # Mark done and unlock next subtask
  def complete!
    transaction do
      update!(status: :done)
      task.unlock_next_subtask!
    end
  end
  
  # Generate artifact file path
  def artifact_path(artifact_name)
    File.join(Rails.root, artifact_name)
  end
  
  # Write to artifact file
  def write_to_artifact(artifact_name, content)
    path = artifact_path(artifact_name)
    ticket_section = "\n## [#{task.ticket_id}] #{task.name}\n"
    ticket_section += "Owner/Agent: #{assigned_agent_name}\n"
    ticket_section += "Date: #{Date.today}\n"
    ticket_section += "Status: #{status}\n\n"
    ticket_section += content
    ticket_section += "\n\n---\n"
    
    File.open(path, 'a') { |f| f.write(ticket_section) }
  end
  
  private
  
  def generate_subtask_id
    self.subtask_id ||= "#{task.ticket_id}-#{assigned_agent_name}-#{SecureRandom.hex(3)}"
  end
end
