# frozen_string_literal: true

module RubyLLM
  module MCP
    class Elicitation
      ACCEPT_ACTION = "accept"
      CANCEL_ACTION = "cancel"
      REJECT_ACTION = "reject"

      attr_writer :structured_response
      attr_reader :id, :requested_schema

      def initialize(coordinator, result)
        @coordinator = coordinator
        @result = result
        @id = result.id

        @message = @result.params["message"]
        @requested_schema = @result.params["requestedSchema"]

        # Async support
        @deferred = false
        @async_response = nil
        @timeout = nil
      end

      def execute
        handler = @coordinator.elicitation_callback

        if Handlers.handler_class?(handler)
          execute_with_handler_class(handler)
        else
          execute_with_block
        end
      end

      def message
        @result.params["message"]
      end

      def validate_response
        JSON::Validator.validate(@requested_schema, @structured_response)
      end

      # Complete async elicitation with response data
      # @param response_data [Hash] the structured response
      def complete(response_data)
        return unless @deferred

        @structured_response = response_data
        valid = validate_response

        if valid
          @coordinator.elicitation_response(
            id: @id,
            elicitation: { action: ACCEPT_ACTION, content: @structured_response }
          )
        else
          @coordinator.elicitation_response(
            id: @id,
            elicitation: { action: CANCEL_ACTION, content: nil }
          )
        end
      end

      # Cancel async elicitation
      # @param reason [String] cancellation reason
      def cancel_async(reason)
        return unless @deferred

        RubyLLM::MCP.logger.info("Cancelling elicitation #{@id}: #{reason}")
        @coordinator.elicitation_response(
          id: @id,
          elicitation: { action: CANCEL_ACTION, content: nil }
        )
      end

      # Mark as timed out
      def timeout!
        return unless @deferred

        RubyLLM::MCP.logger.warn("Elicitation #{@id} timed out")
        @coordinator.elicitation_response(
          id: @id,
          elicitation: { action: CANCEL_ACTION, content: nil }
        )
      end

      # Get timeout value for this elicitation
      attr_reader :timeout

      private

      # Execute using handler class
      def execute_with_handler_class(handler_class)
        handler_instance = handler_class.new(
          elicitation: self,
          coordinator: @coordinator
        )

        # Store timeout from handler if async
        if handler_instance.respond_to?(:async?) && handler_instance.async?
          @timeout = handler_instance.timeout
        end

        result = handler_instance.call

        # Handle different return types
        case result
        when Hash
          handle_handler_hash_result(result)
        when Handlers::AsyncResponse
          handle_async_response(result)
        when Handlers::Promise
          handle_promise(result)
        when :pending
          handle_pending_response
        when TrueClass, FalseClass
          handle_handler_boolean_result(result)
        else
          RubyLLM::MCP.logger.error("Handler returned unexpected type: #{result.class}")
          @coordinator.elicitation_response(
            id: @id,
            elicitation: { action: CANCEL_ACTION, content: nil }
          )
        end
      rescue StandardError => e
        RubyLLM::MCP.logger.error("Error in elicitation handler: #{e.message}\n#{e.backtrace.join("\n")}")
        @coordinator.elicitation_response(
          id: @id,
          elicitation: { action: CANCEL_ACTION, content: nil }
        )
      end

      # Handle hash result from handler
      def handle_handler_hash_result(result)
        case result[:action]
        when :accept
          @structured_response = result[:response]
          if validate_response
            @coordinator.elicitation_response(
              id: @id,
              elicitation: { action: ACCEPT_ACTION, content: @structured_response }
            )
          else
            @coordinator.elicitation_response(
              id: @id,
              elicitation: { action: CANCEL_ACTION, content: nil }
            )
          end
        when :reject
          @coordinator.elicitation_response(
            id: @id,
            elicitation: { action: REJECT_ACTION, content: nil }
          )
        else # :cancel or unknown action -> cancel
          @coordinator.elicitation_response(
            id: @id,
            elicitation: { action: CANCEL_ACTION, content: nil }
          )
        end
      end

      # Handle async response
      def handle_async_response(async_response)
        @deferred = true
        @async_response = async_response

        # Store in registry
        Handlers::ElicitationRegistry.store(@id, self)

        # Set up completion callback
        async_response.on_complete do |state, data|
          case state
          when :completed
            complete(data)
          when :rejected, :cancelled, :timed_out
            cancel_async(data.to_s)
          end
          Handlers::ElicitationRegistry.remove(@id)
        end
      end

      # Handle promise
      def handle_promise(promise)
        @deferred = true

        # Store in registry
        Handlers::ElicitationRegistry.store(@id, self)

        promise.then do |response_data|
          complete(response_data)
          Handlers::ElicitationRegistry.remove(@id)
        end

        promise.catch do |error|
          RubyLLM::MCP.logger.error("Promise rejected: #{error}")
          cancel_async(error.to_s)
          Handlers::ElicitationRegistry.remove(@id)
        end
      end

      # Handle :pending response
      def handle_pending_response
        @deferred = true

        # Store in registry for later completion
        Handlers::ElicitationRegistry.store(@id, self)
      end

      # Handle boolean result from handler
      def handle_handler_boolean_result(result)
        if result
          valid = validate_response
          if valid
            @coordinator.elicitation_response(
              id: @id,
              elicitation: { action: ACCEPT_ACTION, content: @structured_response }
            )
          else
            @coordinator.elicitation_response(
              id: @id,
              elicitation: { action: CANCEL_ACTION, content: nil }
            )
          end
        else
          @coordinator.elicitation_response(
            id: @id,
            elicitation: { action: REJECT_ACTION, content: nil }
          )
        end
      end

      # Execute using block (legacy/backward compatible)
      def execute_with_block
        success = @coordinator.elicitation_callback&.call(self)

        if success
          valid = validate_response
          if valid
            @coordinator.elicitation_response(id: @id,
                                              elicitation: {
                                                action: ACCEPT_ACTION, content: @structured_response
                                              })
          else
            @coordinator.elicitation_response(id: @id, elicitation: { action: CANCEL_ACTION, content: nil })
          end
        else
          @coordinator.elicitation_response(id: @id, elicitation: { action: REJECT_ACTION, content: nil })
        end
      end
    end
  end
end
