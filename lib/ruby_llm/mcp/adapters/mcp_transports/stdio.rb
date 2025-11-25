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

      @coordinator.transport = @native_transport
    end

    def start
      @native_transport.start
    end

    def close
      @native_transport.close
    end

    # Send a JSON-RPC request and return the response
    # This is the interface expected by MCP::Client
    #
    # @param request [Hash] A JSON-RPC request object
    # @return [Hash] A JSON-RPC response object
    def send_request(request:)
      start unless @native_transport.alive?

      unless request["id"] || request[:id]
        request["id"] = SecureRandom.uuid
      end
      result = @native_transport.request(request, wait_for_response: true)

      if result.is_a?(RubyLLM::MCP::Result)
        result.response
      else
        result
      end
    end
  end
end
