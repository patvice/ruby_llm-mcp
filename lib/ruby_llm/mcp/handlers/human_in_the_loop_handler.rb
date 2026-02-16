# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      # Base class for human-in-the-loop approval handlers
      # Provides access to tool details, guards, and async support
      #
      # @example Basic approval handler
      #   class MyApprovalHandler < RubyLLM::MCP::Handlers::HumanInTheLoopHandler
      #     def execute
      #       if safe_tool?(tool_name)
      #         approve
      #       else
      #         deny("Tool requires approval")
      #       end
      #     end
      #
      #     private
      #
      #     def safe_tool?(name)
      #       ["read_file", "list_files"].include?(name)
      #     end
      #   end
      #
      # @example Approval handler with guards and filtering
      #   class SecureApprovalHandler < RubyLLM::MCP::Handlers::HumanInTheLoopHandler
      #     allow_tools "read_file", "list_files"
      #     deny_tools "rm", "delete_all"
      #
      #     guard :check_tool_safety
      #
      #     def execute
      #       return deny("Tool denied") if tool_denied?
      #       approve
      #     end
      #
      #     private
      #
      #     def check_tool_safety
      #       return true if tool_allowed?
      #       "Tool not in safe list"
      #     end
      #   end
      #
      # @example Async approval handler
      #   class AsyncApprovalHandler < RubyLLM::MCP::Handlers::HumanInTheLoopHandler
      #     async_execution timeout: 300
      #
      #     on_timeout :handle_timeout_event
      #
      #     def execute
      #       notify_user(tool_name, parameters)
      #       defer # Returns { status: :deferred, timeout: 300 }
      #     end
      #
      #     private
      #
      #     def handle_timeout_event
      #       deny("User did not respond in time")
      #     end
      #   end
      class HumanInTheLoopHandler
        include Concerns::Options
        include Concerns::Lifecycle
        include Concerns::Logging
        include Concerns::ErrorHandling
        include Concerns::AsyncExecution
        include Concerns::Timeouts
        include Concerns::GuardChecks
        include Concerns::ToolFiltering
        include Concerns::ApprovalActions
        include Concerns::RegistryIntegration

        attr_reader :coordinator

        # Initialize human-in-the-loop handler
        # @param tool_name [String] the tool name
        # @param parameters [Hash] the tool parameters
        # @param approval_id [String] unique identifier for this approval
        # @param coordinator [Object] the coordinator managing the request
        # @param options [Hash] handler-specific options
        def initialize(tool_name:, parameters:, approval_id:, coordinator:, **options)
          @tool_name = tool_name
          @parameters = parameters
          @approval_id = approval_id
          @coordinator = coordinator
          super(**options)
        end
      end
    end
  end
end



