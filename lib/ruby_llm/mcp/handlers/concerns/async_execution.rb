# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      module Concerns
        # Provides async execution capabilities for handlers
        module AsyncExecution
          def self.included(base)
            base.extend(ClassMethods)
          end

          module ClassMethods
            # Mark this handler as async (returns pending response)
            # @param timeout [Integer, nil] optional timeout in seconds
            def async_execution(timeout: nil)
              @async = true
              @async_timeout = timeout if timeout
            end

            # Check if handler is async
            def async?
              @async == true
            end

            # Get async timeout
            attr_reader :async_timeout

            # Inherit async settings from parent classes
            def inherited(subclass)
              super
              subclass.instance_variable_set(:@async, @async)
              subclass.instance_variable_set(:@async_timeout, @async_timeout)
            end
          end

          # Check if this handler instance is async
          def async?
            self.class.async?
          end

          # Get timeout value for this handler
          def timeout
            @options[:timeout] || self.class.async_timeout
          end

          protected

          # Create an async response for deferred completion
          # @param elicitation_id [String, nil] ID for the async operation (auto-detected if not provided)
          # @param timeout_handler [Proc, Symbol, nil] handler for timeout
          # @return [AsyncResponse] async response object
          def defer(elicitation_id: nil, timeout_handler: nil)
            # Auto-detect ID from elicitation or approval_id if not provided
            id = elicitation_id ||
                 (respond_to?(:elicitation) && elicitation&.id) ||
                 (respond_to?(:approval_id) && approval_id)

            raise ArgumentError, "elicitation_id must be provided or handler must have elicitation/approval_id" unless id

            AsyncResponse.new(
              elicitation_id: id,
              timeout: timeout,
              timeout_handler: timeout_handler
            )
          end

          # Create a promise for async operations
          # @return [Promise] promise object
          def create_promise
            Promise.new
          end
        end
      end
    end
  end
end
