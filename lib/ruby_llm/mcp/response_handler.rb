# frozen_string_literal: true

module RubyLLM
  module MCP
    class ResponseHandler
      attr_reader :coordinator, :client

      def initialize(coordinator)
        @coordinator = coordinator
        @client = coordinator.client
      end

      def execute(result) # rubocop:disable Naming/PredicateMethod
        if result.ping?
          coordinator.ping_response(id: result.id)
          true
        elsif result.roots?
          handle_roots_response(result)
          true
        elsif result.sampling?
          handle_sampling_response(result)
          true
        else
          handle_unknown_request(result)
          RubyLLM::MCP.logger.error("MCP client was sent unknown method type and could not respond: #{result.inspect}")
          false
        end
      end

      private

      def handle_roots_response(result)
        if client.roots.active?
          coordinator.roots_list_response(id: result.id, roots: client.roots)
        else
          coordinator.error_response(id: result.id, message: "Roots are not enabled", code: -32_000)
        end
      end

      def handle_sampling_response(result)
        unless MCP.config.sampling.enabled?
          RubyLLM::MCP.logger.info("Sampling is disabled, yet server requested sampling")
          coordinator.error_response(id: result.id, message: "Sampling is disabled", code: -32_000)
          return
        end

        RubyLLM::MCP.logger.info("Sampling response: #{result.inspect}")
        Sample.new(result, coordinator).execute
      end

      def handle_unknown_request(result)
        coordinator.error_response(id: result.id,
                                   message: "Unknown method and could not respond: #{result.method}",
                                   code: -32_000)
      end
    end
  end
end
