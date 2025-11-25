# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
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

        register_transport(:sse, RubyLLM::MCP::Native::Transports::SSE)
        register_transport(:stdio, RubyLLM::MCP::Native::Transports::Stdio)
        register_transport(:streamable, RubyLLM::MCP::Native::Transports::StreamableHTTP)
        register_transport(:streamable_http, RubyLLM::MCP::Native::Transports::StreamableHTTP)

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
            @transport_protocol = nil
            @transport_protocol = build_transport
          end

          @transport_protocol ||= build_transport
        end

        private

        def build_transport
          unless RubyLLM::MCP::Native::Transport.transports.key?(transport_type)
            supported_types = RubyLLM::MCP::Native::Transport.transports.keys.join(", ")
            message = "Invalid transport type: :#{transport_type}. Supported types are #{supported_types}"
            raise Errors::InvalidTransportType.new(message: message)
          end

          # Extract and merge options if present (from OAuth helper preparation)
          transport_config = config.dup
          if transport_config[:options]
            options = transport_config.delete(:options)
            transport_config.merge!(options)
          end

          # Handle SSE transport specially - it uses options hash pattern
          if transport_type == :sse
            url = transport_config.delete(:url) || transport_config.delete("url")
            request_timeout = transport_config.delete(:request_timeout) ||
                              transport_config.delete("request_timeout") ||
                              MCP.config.request_timeout
            # Everything else goes into options
            options_hash = transport_config.dup
            transport_config.clear
            transport_config[:url] = url
            transport_config[:request_timeout] = request_timeout
            transport_config[:options] = options_hash
          end

          # Remove OAuth-specific params from transports that don't support them
          # This allows other arbitrary params (like timeout) to pass through for testing
          unless %i[streamable streamable_http sse].include?(transport_type)
            transport_config.delete(:oauth_provider)
            transport_config.delete(:oauth)
          end

          transport_klass = RubyLLM::MCP::Native::Transport.transports[transport_type]
          transport_klass.new(coordinator: coordinator, **transport_config)
        end
      end
    end
  end
end
