# frozen_string_literal: true

module RubyLLM::MCP::Adapters::MCPTransports
  # Custom SSE transport for MCP SDK adapter
  # Wraps the native SSE transport to provide the interface expected by MCP::Client
  class SSE
    attr_reader :native_transport

    def initialize(url:, headers: {}, version: :http2, request_timeout: 10_000)
      # Create a minimal coordinator-like object for the native transport
      @coordinator = CoordinatorStub.new

      @native_transport = RubyLLM::MCP::Native::Transports::SSE.new(
        url: url,
        coordinator: @coordinator,
        request_timeout: request_timeout,
        options: {
          headers: headers,
          version: version
        }
      )
    end

    # Start the SSE connection
    def start
      @native_transport.start
    end

    # Close the SSE connection
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
      result = @native_transport.request(request, add_id: true, wait_for_response: true)

      # Convert Result object to hash expected by MCP::Client
      if result.is_a?(RubyLLM::MCP::Result)
        result.response
      else
        result
      end
    end
  end
end
