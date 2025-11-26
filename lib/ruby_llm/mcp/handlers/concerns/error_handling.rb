# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      module Concerns
        # Provides error handling and logging for handler execution
        module ErrorHandling
          # Wrap call with error handling
          def call
            super
          rescue StandardError => e
            handle_error(e)
            raise
          end

          protected

          # Handle errors during execution
          # @param error [StandardError] the error that occurred
          def handle_error(error)
            logger.error("Error in #{self.class.name}: #{error.message}")
            logger.error(error.backtrace.join("\n"))
          end
        end
      end
    end
  end
end
