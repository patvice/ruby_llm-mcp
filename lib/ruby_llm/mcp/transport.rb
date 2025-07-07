# frozen_string_literal: true

module RubyLLM
  module MCP
    class Transport
      class << self
        def transports
          @transports ||= {}
        end

        def register_transport(transport_type, transport_class)
          transports[transport_type] = transport_class
        end
      end

      extend Forwardable

      register_transport(:sse, RubyLLM::MCP::Transports::SSE)
      register_transport(:stdio, RubyLLM::MCP::Transports::Stdio)
      register_transport(:streamable, RubyLLM::MCP::Transports::StreamableHTTP)
      register_transport(:streamable_http, RubyLLM::MCP::Transports::StreamableHTTP)

      attr_reader :transport_type, :coordinator, :config, :pid

      def initialize(transport_type, coordinator, config:)
        @transport_type = transport_type
        @coordinator = coordinator
        @config = config
        @pid = Process.pid
      end

      def_delegators :transport_protocol, :request, :alive?, :close, :start, :set_protocol_version

      def transport_protocol
        if @pid != Process.pid
          @pid = Process.pid
          @transport = build_transport
          coordinator.restart_transport
        end

        @transport_protocol ||= build_transport
      end

      private

      def build_transport
        unless RubyLLM::MCP::Transport.transports.key?(transport_type)
          supported_types = RubyLLM::MCP::Transport.transports.keys.join(", ")
          message = "Invalid transport type: :#{transport_type}. Supported types are #{supported_types}"
          raise Errors::InvalidTransportType.new(message: message)
        end

        transport_klass = RubyLLM::MCP::Transport.transports[transport_type]
        transport_klass.new(coordinator: coordinator, **config)
      end
    end
  end
end
