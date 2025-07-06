# frozen_string_literal: true

module RubyLLM
  module MCP
    class Progress
      attr_reader :progress_token, :progress, :total, :message, :client

      def initialize(coordinator, progress_handler, progress_data)
        @coordinator = coordinator
        @client = coordinator.client
        @progress_handler = progress_handler

        @progress_token = progress_data["progressToken"]
        @progress = progress_data["progress"]
        @total = progress_data["total"]
        @message = progress_data["message"]
      end

      def execute_progress_handler
        @progress_handler.call(self)
      end

      def to_h
        {
          progress_token: @progress_token,
          progress: @progress,
          total: @total,
          message: @message
        }
      end

      alias to_json to_h
    end
  end
end
