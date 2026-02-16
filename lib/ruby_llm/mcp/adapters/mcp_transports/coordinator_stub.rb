# frozen_string_literal: true

module RubyLLM::MCP::Adapters::MCPTransports
  # Minimal coordinator stub for MCP transports
  # The native transports expect a coordinator object, but for the MCP SDK adapter
  # we don't need to process results (just pass them through)
  # as MCP SDK adapter doesn't methods that requires responsing to the MCP server as of yet.
  class CoordinatorStub
    attr_reader :name, :protocol_version
    attr_accessor :transport

    def initialize(protocol_version:, notification_callback: nil)
      @name = "MCP-SDK-Adapter"
      @protocol_version = protocol_version
      @transport = nil
      @notification_callback = notification_callback
    end

    def process_result(result)
      if result&.notification?
        @notification_callback&.call(result.notification)
        return nil
      end

      return nil if result&.request?

      result
    end

    def client_capabilities
      {} # MCP SDK doesn't provide client capabilities
    end

    def request(body, **options)
      # For notifications (cancelled, etc), we need to send them through the transport
      return nil unless @transport

      @transport.request(body, **options)
    end
  end
end
