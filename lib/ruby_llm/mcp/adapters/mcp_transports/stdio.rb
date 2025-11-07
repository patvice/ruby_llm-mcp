# frozen_string_literal: true

module RubyLLM::MCP::Adapters::MCPTransports
  # Custom Stdio transport for MCP SDK adapter
  # Wraps the native Stdio transport to provide the interface expected by MCP::Client
  class Stdio
    attr_reader :native_transport

    def initialize(command:, args: [], env: {}, request_timeout: 10_000)
      # Create a minimal coordinator-like object for the native transport
      @coordinator = CoordinatorStub.new

      @native_transport = RubyLLM::MCP::Native::Transports::Stdio.new(
        command: command,
        args: args,
        env: env,
        coordinator: @coordinator,
        request_timeout: request_timeout
      )

      # Set transport reference so coordinator can send notifications
      @coordinator.transport = @native_transport
    end

    # Start the stdio process
    def start
      @native_transport.start
    end

    # Close the stdio process
    def close
      @native_transport.close
    end

    # Send a JSON-RPC request and return the response
    # This is the interface expected by MCP::Client
    #
    # @param request [Hash] A JSON-RPC request object
    # @return [Hash] A JSON-RPC response object
    def send_request(request:)
      # Ensure transport is started
      start unless @native_transport.alive?

      # The native transport expects the body without "jsonrpc" key added yet
      # and will add IDs automatically
      result = @native_transport.request(request, add_id: false, wait_for_response: true)

      # Convert Result object to hash expected by MCP::Client
      if result.is_a?(RubyLLM::MCP::Result)
        result.response
      else
        result
      end
    end
  end
end
