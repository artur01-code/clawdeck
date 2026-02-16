module Api
  module V1
    class AgentsController < BaseController
      # GET /api/v1/agents - list all agents for current user
      def index
        @agents = current_user.agents.order(:role_type, :name)
        render json: @agents.map { |agent| agent_json(agent) }
      end

      # POST /api/v1/agents - create new agent
      def create
        @agent = current_user.agents.new(agent_params)
        
        if @agent.save
          render json: agent_json(@agent), status: :created
        else
          render json: { error: @agent.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/agents/:id - update agent
      def update
        @agent = current_user.agents.find(params[:id])
        
        if @agent.update(agent_params)
          render json: agent_json(@agent)
        else
          render json: { error: @agent.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/agents/:id - delete agent
      def destroy
        @agent = current_user.agents.find(params[:id])
        @agent.destroy!
        head :no_content
      end

      private

      def agent_params
        params.require(:agent).permit(:name, :is_dev, :role_type, :emoji)
      end

      def agent_json(agent)
        {
          id: agent.id,
          name: agent.name,
          is_dev: agent.is_dev,
          role_type: agent.role_type,
          emoji: agent.emoji,
          created_at: agent.created_at.iso8601,
          updated_at: agent.updated_at.iso8601
        }
      end
    end
  end
end
