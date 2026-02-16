# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      # Base class for elicitation request handlers
      # Provides access to elicitation object and async support
      #
      # @example Basic elicitation handler
      #   class MyElicitationHandler < RubyLLM::MCP::Handlers::ElicitationHandler
      #     def execute
      #       response = build_response(elicitation)
      #       accept(response)
      #     end
      #   end
      #
      # @example Async elicitation handler
      #   class AsyncElicitationHandler < RubyLLM::MCP::Handlers::ElicitationHandler
      #     async_execution timeout: 300
      #
      #     on_timeout :handle_timeout_event
      #
      #     def execute
      #       notify_user(elicitation)
      #       defer # Returns AsyncResponse
      #     end
      #
      #     private
      #
      #     def handle_timeout_event
      #       reject("Request timed out")
      #     end
      #   end
      class ElicitationHandler
        include Concerns::Options
        include Concerns::Lifecycle
        include Concerns::Logging
        include Concerns::ErrorHandling
        include Concerns::AsyncExecution
        include Concerns::Timeouts
        include Concerns::ElicitationActions
        include Concerns::RegistryIntegration

        attr_reader :coordinator

        # Initialize elicitation handler
        # @param elicitation [RubyLLM::MCP::Elicitation] the elicitation request
        # @param coordinator [Object] the coordinator managing the request
        # @param options [Hash] handler-specific options
        def initialize(elicitation:, coordinator:, **options)
          @elicitation = elicitation
          @coordinator = coordinator
          super(**options)
        end
      end
    end
  end
end




