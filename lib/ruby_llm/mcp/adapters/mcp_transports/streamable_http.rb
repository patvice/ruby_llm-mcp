# frozen_string_literal: true

module RubyLLM::MCP::Adapters::MCPTransports
  # Custom Streamable HTTP transport for MCP SDK adapter
  # Wraps the native StreamableHTTP transport to provide the interface expected by MCP::Client
  class StreamableHTTP
    attr_reader :native_transport

    def initialize(url:, headers: {}, version: :http2, request_timeout: 10_000, # rubocop:disable Metrics/ParameterLists
                   reconnection: {}, oauth_provider: nil, rate_limit: nil, session_id: nil)
      # Create a minimal coordinator-like object for the native transport
      @coordinator = CoordinatorStub.new
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

      # Set the transport reference on the coordinator so it can send requests
      @coordinator.transport = @native_transport
    end

    # Start the streamable HTTP connection
    # This only initializes the transport layer, not the MCP protocol
    def start
      @native_transport.start
    end

    # Close the streamable HTTP connection
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

      # Pass the request through to native transport
      # add_id: true because MCP SDK provides requests without IDs
      result = @native_transport.request(request, add_id: true, wait_for_response: true)

      # Convert Result object to hash expected by MCP::Client
      if result.is_a?(RubyLLM::MCP::Result)
        result.response
      else
        result
      end
    end

    private

    def perform_initialization
      # Send initialization request
      init_request = RubyLLM::MCP::Native::Requests::Initialization.new(@coordinator).initialize_body
      result = @native_transport.request(init_request, add_id: true, wait_for_response: true)

      if result.is_a?(RubyLLM::MCP::Result) && result.error?
        raise RubyLLM::MCP::Errors::TransportError.new(
          message: "Initialization failed: #{result.error}",
          error: result.error
        )
      end

      initialized_notification = {
        "jsonrpc" => "2.0",
        "method" => "notifications/initialized"
      }
      @native_transport.request(initialized_notification, add_id: false, wait_for_response: false)

      @initialized = true
    end
  end
end
