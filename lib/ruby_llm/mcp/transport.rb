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

        transport_config = config.dup
        oauth_provider = create_oauth_provider(transport_config) if oauth_config_present?(transport_config)

        transport_klass = RubyLLM::MCP::Transport.transports[transport_type]
        transport_klass.new(coordinator: coordinator, oauth_provider: oauth_provider, **transport_config)
      end

      # Check if OAuth configuration is present
      def oauth_config_present?(config)
        oauth_config = config[:oauth] || config["oauth"]
        !oauth_config.nil? && !oauth_config.empty?
      end

      # Create OAuth provider from configuration
      def create_oauth_provider(config)
        oauth_config = config.delete(:oauth) || config.delete("oauth")
        return nil unless oauth_config

        # Determine server URL based on transport type
        server_url = determine_server_url(config)
        return nil unless server_url

        redirect_uri = oauth_config[:redirect_uri] || oauth_config["redirect_uri"] || "http://localhost:8080/callback"
        scope = oauth_config[:scope] || oauth_config["scope"]
        storage = oauth_config[:storage] || oauth_config["storage"]

        RubyLLM::MCP::Auth::OAuthProvider.new(
          server_url: server_url,
          redirect_uri: redirect_uri,
          scope: scope,
          logger: MCP.logger,
          storage: storage
        )
      end

      # Determine server URL from transport config
      def determine_server_url(config)
        config[:url] || config["url"]
      end
    end
  end
end
