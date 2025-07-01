# frozen_string_literal: true

module RubyLLM
  module MCP
    class ResponseHandler
      attr_reader :coordinator, :client

      def initialize(coordinator)
        @coordinator = coordinator
        @client = coordinator.client
      end

      def execute(result)
        if result.ping?
          coordinator.ping_response(id: result.id)
          true
        elsif result.roots?
          coordinator.roots_response(id: result.id)
          true
        elsif result.sampling?
          handle_sampling_response(result)
          true
        else
          # Handle server-initiated requests
          # Currently, we do not support any client operations but will
          raise RubyLLM::MCP::Errors::UnknownRequest.new(message: "Unknown request type: #{result.inspect}")
        end
      end

      private

      def handle_sampling_response(result)
        RubyLLM::MCP.logger.info("Sampling response: #{result.inspect}")
        Sample.new(result, coordinator).execute
      end
    end
  end
end
