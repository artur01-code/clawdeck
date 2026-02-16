module Api
  module V1
    class SubtasksController < BaseController
      before_action :set_task, only: [:index]
      before_action :set_subtask, only: [:show, :update, :complete]

      # GET /api/v1/tasks/:task_id/subtasks - list subtasks for a task
      def index
        @subtasks = @task.subtasks.order(:created_at)
        render json: @subtasks.map { |st| subtask_json(st) }
      end

      # GET /api/v1/subtasks/:id - get single subtask
      def show
        render json: subtask_json(@subtask)
      end

      # PATCH /api/v1/subtasks/:id - update subtask
      def update
        if @subtask.update(subtask_params)
          render json: subtask_json(@subtask)
        else
          render json: { error: @subtask.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/subtasks/:id/complete - mark subtask done
      def complete
        @subtask.complete!
        render json: subtask_json(@subtask)
      end

      private

      def set_task
        @task = current_user.tasks.find(params[:task_id])
      end

      def set_subtask
        @subtask = current_user.tasks.joins(:subtasks).find_by!(subtasks: { id: params[:id] })
      end

      def subtask_params
        params.require(:subtask).permit(:status, :notes, :blocked_reason)
      end

      def subtask_json(subtask)
        {
          id: subtask.id,
          subtask_id: subtask.subtask_id,
          task_id: subtask.task_id,
          assigned_agent_name: subtask.assigned_agent_name,
          role: subtask.role,
          status: subtask.status,
          depends_on_subtask_ids: subtask.depends_on_subtask_ids,
          artifact_targets: subtask.artifact_targets,
          pending_agent_registration: subtask.pending_agent_registration,
          visible_to_agent: subtask.visible_to_agent?,
          blocked_reason: subtask.blocked_reason,
          notes: subtask.notes,
          created_at: subtask.created_at.iso8601,
          updated_at: subtask.updated_at.iso8601
        }
      end
    end
  end
end
