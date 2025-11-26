# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      # Promise implementation for async operations
      class Promise
        attr_reader :state, :value, :reason

      # Initialize a new promise
      def initialize
        @state = :pending
        @value = nil
        @reason = nil
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @then_callbacks = []
        @catch_callbacks = []
      end

        # Register a callback for successful resolution
        # @param callback [Proc] callback to execute on resolution
        # @return [Promise] returns self for chaining
        def then(&callback)
          should_execute = false
          value_to_use = nil

          @mutex.synchronize do
            if @state == :fulfilled
              # Already fulfilled, will execute immediately
              should_execute = true
              value_to_use = @value
            elsif @state == :pending
              # Still pending, register callback
              @then_callbacks << callback
            end
          end

          # Execute outside mutex
          execute_callback_sync(callback, value_to_use) if should_execute
          self
        end

        # Register a callback for rejection
        # @param callback [Proc] callback to execute on rejection
        # @return [Promise] returns self for chaining
        def catch(&callback)
          should_execute = false
          reason_to_use = nil

          @mutex.synchronize do
            if @state == :rejected
              # Already rejected, will execute immediately
              should_execute = true
              reason_to_use = @reason
            elsif @state == :pending
              # Still pending, register callback
              @catch_callbacks << callback
            end
          end

          # Execute outside mutex
          execute_callback_sync(callback, reason_to_use) if should_execute
          self
        end

        # Resolve the promise with a value
        # @param value [Object] the resolved value
        def resolve(value)
          callbacks_to_execute = nil

          @mutex.synchronize do
            return unless @state == :pending

            @state = :fulfilled
            @value = value

            # Capture callbacks to execute outside mutex
            callbacks_to_execute = @then_callbacks.dup
            @then_callbacks.clear
            @catch_callbacks.clear

            # Signal waiting threads
            @condition.broadcast
          end

          # Execute callbacks outside mutex to avoid deadlocks
          # Use synchronous execution to maintain order and allow tests to work
          callbacks_to_execute&.each do |callback|
            execute_callback_sync(callback, value)
          end
        end

        # Reject the promise with a reason
        # @param reason [Object] the rejection reason
        def reject(reason)
          callbacks_to_execute = nil

          @mutex.synchronize do
            return unless @state == :pending

            @state = :rejected
            @reason = reason

            # Capture callbacks to execute outside mutex
            callbacks_to_execute = @catch_callbacks.dup
            @then_callbacks.clear
            @catch_callbacks.clear

            # Signal waiting threads
            @condition.broadcast
          end

          # Execute callbacks outside mutex to avoid deadlocks
          # Use synchronous execution to maintain order and allow tests to work
          callbacks_to_execute&.each do |callback|
            execute_callback_sync(callback, reason)
          end
        end

        # Check if promise is pending
        def pending?
          @state == :pending
        end

        # Check if promise is fulfilled
        def fulfilled?
          @state == :fulfilled
        end

        # Check if promise is rejected
        def rejected?
          @state == :rejected
        end

        # Check if promise is settled (fulfilled or rejected)
        def settled?
          !pending?
        end

        # Wait for promise to settle with optional timeout
        # @param timeout [Numeric, nil] timeout in seconds
        # @return [Object] resolved value or raises error
        def wait(timeout: nil)
          @mutex.synchronize do
            # Wait until promise is settled
            if timeout
              deadline = Time.now + timeout
              while pending?
                remaining = deadline - Time.now
                if remaining <= 0
                  raise Timeout::Error, "Promise timed out after #{timeout} seconds"
                end
                @condition.wait(@mutex, remaining)
              end
            else
              @condition.wait(@mutex) while pending?
            end

            # Return value or raise error
            return @value if fulfilled?
            raise @reason if rejected?
          end
        end

        private

        # Execute a callback safely
        # Note: Executes in background thread to avoid blocking
        def execute_callback(callback, arg)
          Thread.new do
            begin
              callback.call(arg)
            rescue StandardError => e
              RubyLLM::MCP.logger.error(
                "Error in promise callback: #{e.message}\n#{e.backtrace.join("\n")}"
              )
            end
          end
        end

        # Execute a callback synchronously (for testing and immediate execution)
        def execute_callback_sync(callback, arg)
          begin
            callback.call(arg)
          rescue StandardError => e
            RubyLLM::MCP.logger.error(
              "Error in promise callback: #{e.message}\n#{e.backtrace.join("\n")}"
            )
          end
        end
      end
    end
  end
end
