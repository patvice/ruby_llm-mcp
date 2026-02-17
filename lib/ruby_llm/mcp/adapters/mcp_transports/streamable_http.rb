# frozen_string_literal: true

module RubyLLM::MCP::Adapters::MCPTransports
  # Custom Streamable HTTP transport for MCP SDK adapter
  # Wraps the native StreamableHTTP transport to provide the interface expected by MCP::Client
  class StreamableHTTP
    attr_reader :native_transport

    def initialize(url:, headers: {}, version: :http2, request_timeout: 10_000, # rubocop:disable Metrics/ParameterLists
                   reconnection: {}, oauth_provider: nil, rate_limit: nil, session_id: nil,
                   protocol_version: RubyLLM::MCP.config.protocol_version, notification_callback: nil)
      # Create a minimal coordinator-like object for the native transport
      @coordinator = CoordinatorStub.new(
        protocol_version: protocol_version,
        notification_callback: notification_callback
      )
      @initialized = false

      @native_transport = RubyLLM::MCP::Native::Transports::StreamableHTTP.new(
        url: url,
        headers: headers,
        version: version,
        coordinator: @coordinator,
        request_timeout: request_timeout,
        reconnection: reconnection,
        oauth_provider: oauth_provider,
        rate_limit: rate_limit,
        session_id: session_id
      )

      @coordinator.transport = @native_transport
    end

    def start
      @native_transport.start
    end

    def close
      @initialized = false
      @native_transport.close
    end

    # Send a JSON-RPC request and return the response
    # This is the interface expected by MCP::Client
    #
    # @param request [Hash] A JSON-RPC request object
    # @return [Hash] A JSON-RPC response object
    def send_request(request:)
      # Auto-initialize on first non-initialize request
      # Streamable HTTP servers require initialization before other requests
      unless @initialized || request[:method] == "initialize" || request["method"] == "initialize"
        perform_initialization
      end

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

    private

    def perform_initialization
      # Send initialization request
      init_request = RubyLLM::MCP::Native::Messages::Requests.initialize(
        protocol_version: @coordinator.protocol_version,
        capabilities: @coordinator.client_capabilities
      )
      result = @native_transport.request(init_request, wait_for_response: true)

      if result.is_a?(RubyLLM::MCP::Result) && result.error?
        raise RubyLLM::MCP::Errors::TransportError.new(
          message: "Initialization failed: #{result.error}",
          error: result.error
        )
      end

      initialized_notification = RubyLLM::MCP::Native::Messages::Notifications.initialized
      @native_transport.request(initialized_notification, wait_for_response: false)

      @initialized = true
    end
  end
end
