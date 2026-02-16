class Agent < ApplicationRecord
  belongs_to :user
  
  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :role_type, inclusion: { in: %w[PO UX DEV QA DEVOPS ANALYST], allow_nil: true }
  
  # Default agents by role
  DEFAULTS = [
    { name: "PO", role_type: "PO", is_dev: false, emoji: "📋" },
    { name: "Designer", role_type: "UX", is_dev: false, emoji: "🎨" },
    { name: "Swift-Dev", role_type: "DEV", is_dev: true, emoji: "📱" },
    { name: "Backend-Dev", role_type: "DEV", is_dev: true, emoji: "⚙️" },
    { name: "QA", role_type: "QA", is_dev: false, emoji: "✅" }
  ].freeze
  
  # Create default agents for user if none exist
  def self.ensure_defaults_for_user(user)
    return if user.agents.exists?
    
    DEFAULTS.each do |attrs|
      user.agents.create!(attrs)
    end
  end
  
  def dev_agent?
    is_dev
  end
end
