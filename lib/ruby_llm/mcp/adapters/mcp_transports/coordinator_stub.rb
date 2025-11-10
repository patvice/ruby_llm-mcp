# frozen_string_literal: true

module RubyLLM::MCP::Adapters::MCPTransports
  # Minimal coordinator stub for MCP transports
  # The native transports expect a coordinator object, but for the MCP SDK adapter
  # we don't need to process results (just pass them through)
  # as MCP SDK adapter doesn't methods that requires responsing to the MCP server as of yet.
  class CoordinatorStub
    attr_reader :name, :protocol_version
    attr_accessor :transport

    def initialize
      @name = "MCP-SDK-Adapter"
      @protocol_version = RubyLLM::MCP::Native::Protocol.default_negotiated_version
      @transport = nil
    end

    def process_result(result)
      result
    end

    def client_capabilities
      {} # MCP SDK doesn't provide client capabilities
    end

    def request(body, **)
      # For notifications (cancelled, etc), we need to send them through the transport
      return nil unless @transport

      @transport.request(body, **)
    end
  end
end
