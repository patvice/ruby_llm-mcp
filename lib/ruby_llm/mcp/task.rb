# frozen_string_literal: true

module RubyLLM
  module MCP
    class Task
      attr_reader :adapter, :task_id, :status, :status_message, :created_at,
                  :last_updated_at, :ttl, :poll_interval

      def initialize(adapter, task_response)
        @adapter = adapter
        @task_id = task_response["taskId"]
        @status = task_response["status"]
        @status_message = task_response["statusMessage"]
        @created_at = task_response["createdAt"]
        @last_updated_at = task_response["lastUpdatedAt"]
        @ttl = task_response["ttl"]
        @poll_interval = task_response["pollInterval"]
      end

      def working?
        status == "working"
      end

      def input_required?
        status == "input_required"
      end

      def completed?
        status == "completed"
      end

      def failed?
        status == "failed"
      end

      def cancelled?
        status == "cancelled"
      end

      def result
        @adapter.task_result(task_id: task_id).value
      end

      def cancel
        self.class.new(@adapter, @adapter.task_cancel(task_id: task_id).value)
      end

      def refresh
        self.class.new(@adapter, @adapter.task_get(task_id: task_id).value)
      end

      def to_h
        {
          task_id: task_id,
          status: status,
          status_message: status_message,
          created_at: created_at,
          last_updated_at: last_updated_at,
          ttl: ttl,
          poll_interval: poll_interval
        }
      end
    end
  end
end
