# frozen_string_literal: true

module RubyLLM::MCP::Adapters::MCPTransports
  # Custom SSE transport for MCP SDK adapter
  # Wraps the native SSE transport to provide the interface expected by MCP::Client
  class SSE
    attr_reader :native_transport

    def initialize(url:, headers: {}, version: :http2, request_timeout: 10_000, # rubocop:disable Metrics/ParameterLists
                   protocol_version: RubyLLM::MCP.config.protocol_version, notification_callback: nil)
      # Create a minimal coordinator-like object for the native transport
      @coordinator = CoordinatorStub.new(
        protocol_version: protocol_version,
        notification_callback: notification_callback
      )

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
