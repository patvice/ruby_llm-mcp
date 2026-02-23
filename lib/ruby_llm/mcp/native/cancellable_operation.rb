# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      # Wraps server-initiated requests to support cancellation.
      # The operation tracks terminal state so cancellation outcomes are explicit.
      class CancellableOperation
        attr_reader :request_id

        def initialize(request_id)
          @request_id = request_id
          @state = :pending
          @mutex = Mutex.new
          @thread = nil
          @result = nil
          @error = nil
        end

        def cancelled?
          @mutex.synchronize { %i[cancelling cancelled].include?(@state) }
        end

        # @return [Symbol] :cancelled, :already_cancelled, :already_completed
        def cancel
          thread_to_cancel = nil

          @mutex.synchronize do
            case @state
            when :cancelled, :cancelling
              return :already_cancelled
            when :completed
              return :already_completed
            when :pending
              @state = :cancelled
              return :cancelled
            when :running
              @state = :cancelling
              thread_to_cancel = @thread
            end
          end

          if thread_to_cancel&.alive?
            thread_to_cancel.raise(
              Errors::RequestCancelled.new(
                message: "Request #{@request_id} was cancelled",
                request_id: @request_id
              )
            )
          else
            @mutex.synchronize do
              @state = :cancelled if @state == :cancelling
            end
          end

          :cancelled
        end

        # Execute a block in a separate thread so cancellation can interrupt execution.
        # Returns the block result or re-raises non-cancellation exceptions.
        def execute(&)
          return nil if cancelled?

          worker = @mutex.synchronize do
            return nil if %i[cancelled cancelling].include?(@state)

            @state = :running
            @thread = Thread.new do
              Thread.current.abort_on_exception = false
              begin
                @result = yield
              rescue Errors::RequestCancelled, StandardError => e
                @error = e
              end
            end
          end

          worker.join
          raise @error if @error && !@error.is_a?(Errors::RequestCancelled)

          @result
        ensure
          @mutex.synchronize do
            if @state == :running || @state == :cancelling
              @state = @error.is_a?(Errors::RequestCancelled) ? :cancelled : :completed
            end
            @thread = nil
          end
        end

        def state
          @mutex.synchronize { @state }
        end

        def thread
          @mutex.synchronize { @thread }
        end
      end
    end
  end
end
