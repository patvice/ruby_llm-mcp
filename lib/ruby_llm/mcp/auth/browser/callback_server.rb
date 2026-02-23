# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      module Browser
        # Callback server wrapper for clean shutdown
        # Manages server lifecycle and thread coordination
        class CallbackServer
          def initialize(server, thread, stop_proc, start_proc = nil)
            @server = server
            @thread = thread
            @stop_proc = stop_proc
            @start_proc = start_proc || -> {}
          end

          # Start callback processing loop
          def start
            @start_proc.call
          end

          # Shutdown server and cleanup resources
          # @return [nil] always returns nil
          def shutdown
            @stop_proc.call
            @server.close unless @server.closed?
            @thread.join(5) # Wait max 5 seconds for thread to finish
          rescue StandardError
            # Ignore shutdown errors
            nil
          end
        end
      end
    end
  end
end
