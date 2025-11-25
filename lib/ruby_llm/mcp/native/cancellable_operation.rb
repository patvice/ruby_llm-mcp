# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      # Wraps server-initiated requests to support cancellation
      # Executes the request in a separate thread that can be terminated on cancellation
      class CancellableOperation
        attr_reader :request_id, :thread

        def initialize(request_id)
          @request_id = request_id
          @cancelled = false
          @mutex = Mutex.new
          @thread = nil
          @result = nil
          @error = nil
        end

        def cancelled?
          @mutex.synchronize { @cancelled }
        end

        def cancel
          @mutex.synchronize { @cancelled = true }
          if @thread&.alive?
            @thread.raise(Errors::RequestCancelled.new(
                            message: "Request #{@request_id} was cancelled",
                            request_id: @request_id
                          ))
          end
        end

        # Execute a block in a separate thread
        # This allows the thread to be terminated if cancellation is requested
        # Returns the result of the block or re-raises any error that occurred
        def execute(&)
          @thread = Thread.new do
            Thread.current.abort_on_exception = false
            begin
              @result = yield
            rescue Errors::RequestCancelled, StandardError => e
              @error = e
            end
          end

          @thread.join
          raise @error if @error && !@error.is_a?(Errors::RequestCancelled)

          @result
        ensure
          @thread = nil
        end
      end
    end
  end
end
