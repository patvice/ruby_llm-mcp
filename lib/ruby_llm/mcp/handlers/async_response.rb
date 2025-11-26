# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      # Represents an async response for deferred completion
      class AsyncResponse
        attr_reader :elicitation_id, :state, :result, :error

        VALID_STATES = %i[pending completed rejected cancelled timed_out].freeze

        # Initialize async response
        # @param elicitation_id [String] ID of the elicitation
        # @param timeout [Integer, nil] optional timeout in seconds
        # @param timeout_handler [Proc, Symbol, nil] handler for timeout
        def initialize(elicitation_id:, timeout: nil, timeout_handler: nil)
          @elicitation_id = elicitation_id
          @state = :pending
          @result = nil
          @error = nil
          @mutex = Mutex.new
          @timeout = timeout
          @timeout_handler = timeout_handler
          @completion_callbacks = []
          @created_at = Time.now

          RubyLLM::MCP.logger.debug("AsyncResponse created for #{@elicitation_id} with timeout: #{@timeout || 'none'}")
          schedule_timeout if @timeout
        end

    # Complete the async operation with data
    # @param data [Object] the completion data
    def complete(data)
      callbacks_to_execute = nil

      transitioned = transition_state(:completed) do
        @result = data
        callbacks_to_execute = @completion_callbacks.dup
      end

      if transitioned
        duration = Time.now - @created_at
        RubyLLM::MCP.logger.debug("AsyncResponse #{@elicitation_id} completed after #{duration.round(3)}s")
      end

      # Execute callbacks outside mutex to avoid deadlocks
      execute_callbacks_safely(callbacks_to_execute, :completed, data) if transitioned && callbacks_to_execute
    end

    # Reject the async operation
    # @param reason [String] reason for rejection
    def reject(reason)
      callbacks_to_execute = nil

      transitioned = transition_state(:rejected) do
        @error = reason
        callbacks_to_execute = @completion_callbacks.dup
      end

      execute_callbacks_safely(callbacks_to_execute, :rejected, reason) if transitioned && callbacks_to_execute
    end

    # Cancel the async operation
    # @param reason [String] reason for cancellation
    def cancel(reason)
      callbacks_to_execute = nil

      transitioned = transition_state(:cancelled) do
        @error = reason
        callbacks_to_execute = @completion_callbacks.dup
      end

      execute_callbacks_safely(callbacks_to_execute, :cancelled, reason) if transitioned && callbacks_to_execute
    end

    # Mark as timed out
    def timeout!
      callbacks_to_execute = nil

      transitioned = transition_state(:timed_out) do
        @error = "Operation timed out"
        callbacks_to_execute = @completion_callbacks.dup
      end

      execute_callbacks_safely(callbacks_to_execute, :timed_out, @error) if transitioned && callbacks_to_execute
    end

        # Register a callback for when operation completes/fails
        # @param callback [Proc] callback to execute
        def on_complete(&callback)
          @mutex.synchronize do
            @completion_callbacks << callback
          end
        end

        # Check if operation is pending
        def pending?
          @state == :pending
        end

        # Check if operation is completed
        def completed?
          @state == :completed
        end

        # Check if operation is rejected
        def rejected?
          @state == :rejected
        end

        # Check if operation is cancelled
        def cancelled?
          @state == :cancelled
        end

        # Check if operation timed out
        def timed_out?
          @state == :timed_out
        end

        # Check if operation is finished (any terminal state)
        def finished?
          !pending?
        end

        private

        # Transition to new state (thread-safe)
        def transition_state(new_state)
          @mutex.synchronize do
            return false unless @state == :pending
            return false unless VALID_STATES.include?(new_state)

            @state = new_state
            yield if block_given?
            true
          end
        end

    # Execute callbacks safely in isolation
    # @param callbacks [Array] callbacks to execute
    # @param state [Symbol] the state to pass to callbacks
    # @param data [Object] the data to pass to callbacks
    def execute_callbacks_safely(callbacks, state, data)
      return unless callbacks

      callbacks.each do |callback|
        begin
          callback.call(state, data)
        rescue StandardError => e
          RubyLLM::MCP.logger.error(
            "Error in async response callback: #{e.message}\n#{e.backtrace.join("\n")}"
          )
          # Continue executing other callbacks even if one fails
        end
      end
    end

        # Schedule timeout check
        def schedule_timeout
          Thread.new do
            sleep @timeout
            if pending?
              timeout!
              handle_timeout
            end
          end
        end

        # Handle timeout event
        def handle_timeout
          if @timeout_handler
            if @timeout_handler.is_a?(Proc)
              @timeout_handler.call
            end
          end
        rescue StandardError => e
          RubyLLM::MCP.logger.error(
            "Error in timeout handler: #{e.message}\n#{e.backtrace.join("\n")}"
          )
        end
      end
    end
  end
end
