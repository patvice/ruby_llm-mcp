# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      # Detect if a handler is a class (vs a block/proc/lambda)
      # @param handler [Object] the handler to check
      # @return [Boolean] true if handler is a class
      def self.handler_class?(handler)
        handler.is_a?(Class) || (handler.respond_to?(:new) && !handler.respond_to?(:call))
      end
    end
  end
end

# Load concerns first (handlers depend on them)
require_relative "handlers/concerns/options"
require_relative "handlers/concerns/lifecycle"
require_relative "handlers/concerns/logging"
require_relative "handlers/concerns/error_handling"
require_relative "handlers/concerns/async_execution"
require_relative "handlers/concerns/timeouts"
require_relative "handlers/concerns/guard_checks"
require_relative "handlers/concerns/tool_filtering"
require_relative "handlers/concerns/model_filtering"
require_relative "handlers/concerns/approval_actions"
require_relative "handlers/concerns/elicitation_actions"
require_relative "handlers/concerns/sampling_actions"
require_relative "handlers/concerns/registry_integration"

# Load core handler infrastructure
require_relative "handlers/promise"
require_relative "handlers/async_response"

# Load registries
require_relative "handlers/elicitation_registry"
require_relative "handlers/human_in_the_loop_registry"

# Load handler classes
require_relative "handlers/sampling_handler"
require_relative "handlers/elicitation_handler"
require_relative "handlers/human_in_the_loop_handler"
