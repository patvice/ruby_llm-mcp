# frozen_string_literal: true

module RubyLLM
  module MCP
    class Configuration
      class AdapterConfig
        VALID_ADAPTERS = %i[ruby_llm mcp_sdk].freeze
        VALID_TRANSPORTS = %i[stdio sse streamable streamable_http http].freeze

        attr_accessor :default_adapter

        def initialize
          @default_adapter = :ruby_llm
        end

        def validate!(adapter:, transport:)
          validate_adapter!(adapter)
          validate_transport!(transport)
          validate_adapter_transport_combination!(adapter, transport)
        end

        def adapter_for(config)
          config[:sdk] || config[:adapter] || @default_adapter
        end

        private

        def validate_adapter!(adapter)
          unless VALID_ADAPTERS.include?(adapter)
            raise Errors::AdapterConfigurationError.new(
              message: "Invalid adapter '#{adapter}'. Valid options: #{VALID_ADAPTERS.join(', ')}"
            )
          end
        end

        def validate_transport!(transport)
          unless VALID_TRANSPORTS.include?(transport)
            raise Errors::AdapterConfigurationError.new(
              message: "Invalid transport '#{transport}'. Valid options: #{VALID_TRANSPORTS.join(', ')}"
            )
          end
        end

        def validate_adapter_transport_combination!(adapter, transport)
          # SSE is supported by both ruby_llm and mcp_sdk adapters
          # No validation needed at this time
        end
      end

      class Sampling
        attr_accessor :enabled, :tools, :context
        attr_writer :preferred_model, :handler

        def initialize
          set_defaults
        end

        def reset!
          set_defaults
        end

        def guard(&block)
          @guard = block if block_given?
          @guard
        end

        def preferred_model(&block)
          @preferred_model = block if block_given?
          @preferred_model
        end

        # Set or get the handler (class or block)
        # @param handler_class [Class, nil] handler class
        # @param options [Hash] options to pass to handler
        # @return [Object] the current handler
        def handler(handler_class = nil, **options)
          if handler_class
            @handler = if options.any?
                         { class: handler_class, options: options }
                       else
                         handler_class
                       end
          end
          @handler
        end

        def enabled?
          @enabled
        end

        private

        def set_defaults
          @enabled = false
          @tools = false
          @context = true
          @preferred_model = nil
          @guard = nil
          @handler = nil
        end
      end

      class Elicitation
        attr_accessor :form, :url

        def initialize
          @form = true
          @url = false
        end

        def enabled?
          @form || @url
        end
      end

      class Tasks
        attr_accessor :enabled

        def initialize
          @enabled = false
        end

        def enabled?
          @enabled
        end
      end

      class OAuth
        attr_accessor :client_name,
                      :client_uri,
                      :software_id,
                      :software_version,
                      :logo_uri,
                      :contacts,
                      :tos_uri,
                      :policy_uri,
                      :jwks_uri,
                      :jwks,
                      :browser_success_page,
                      :browser_error_page

        def initialize
          @client_name = "RubyLLM MCP Client"
          @client_uri = nil
          @software_id = "ruby_llm-mcp"
          @software_version = RubyLLM::MCP::VERSION
          @logo_uri = nil
          @contacts = nil
          @tos_uri = nil
          @policy_uri = nil
          @jwks_uri = nil
          @jwks = nil
          @browser_success_page = nil
          @browser_error_page = nil
        end
      end

      class ConfigFile
        attr_reader :file_path

        def initialize(file_path)
          @file_path = file_path
        end

        def parse
          @parse ||= if @file_path && File.exist?(@file_path)
                       config = parse_config_file
                       load_mcps_config(config)
                     else
                       []
                     end
        end

        private

        def parse_config_file
          output = ERB.new(File.read(@file_path)).result

          if [".yaml", ".yml"].include?(File.extname(@file_path))
            YAML.safe_load(output, symbolize_names: true)
          else
            JSON.parse(output, symbolize_names: true)
          end
        end

        def load_mcps_config(config)
          return [] unless config.key?(:mcp_servers)

          config[:mcp_servers].map do |name, configuration|
            {
              name: name,
              transport_type: configuration.delete(:transport_type),
              start: false,
              config: configuration
            }
          end
        end
      end

      attr_accessor :request_timeout,
                    :log_file,
                    :log_level,
                    :roots,
                    :sampling,
                    :elicitation,
                    :tasks,
                    :max_connections,
                    :pool_timeout,
                    :config_path,
                    :launch_control,
                    :on_logging_level,
                    :adapter_config,
                    :oauth

      attr_reader :extensions, :protocol_track
      attr_writer :logger, :mcp_configuration, :protocol_version

      REQUEST_TIMEOUT_DEFAULT = 8000
      VALID_PROTOCOL_TRACKS = %i[stable draft].freeze

      def initialize
        @sampling = Sampling.new
        @elicitation = Elicitation.new
        @tasks = Tasks.new
        @adapter_config = AdapterConfig.new
        @extensions = Extensions::Configuration.new
        @oauth = OAuth.new
        set_defaults
      end

      def reset!
        set_defaults
      end

      def logger
        @logger ||= Logger.new(
          log_file,
          progname: "RubyLLM::MCP",
          level: log_level
        )
      end

      # Convenience method for setting default adapter
      def default_adapter=(adapter)
        @adapter_config.default_adapter = adapter
      end

      def default_adapter
        @adapter_config.default_adapter
      end

      # Validate MCP configuration before use
      def mcp_configuration
        configs = @mcp_configuration + load_mcps_config
        validate_configurations!(configs)
        configs
      end

      def on_progress(&block)
        @on_progress = block if block_given?
        @on_progress
      end

      def on_human_in_the_loop(handler_class = nil, **options)
        if block_given?
          raise ArgumentError, "Block-based human-in-the-loop callbacks are no longer supported. Use a handler class."
        end

        if handler_class
          @on_human_in_the_loop = { class: handler_class, options: options }
        end
        @on_human_in_the_loop
      end

      def on_logging(&block)
        @on_logging = block if block_given?
        @on_logging
      end

      def on_elicitation(&block)
        @on_elicitation = block if block_given?
        @on_elicitation
      end

      def protocol_track=(value)
        track = value.to_sym
        unless VALID_PROTOCOL_TRACKS.include?(track)
          raise ArgumentError,
                "Invalid protocol track '#{value}'. Valid options: #{VALID_PROTOCOL_TRACKS.join(', ')}"
        end

        @protocol_track = track
      end

      # Returns the effective protocol version:
      # explicit protocol_version > protocol_track-derived default.
      def protocol_version
        return @protocol_version unless @protocol_version.nil?

        return Native::Protocol.draft_version if @protocol_track == :draft

        Native::Protocol.latest_version
      end

      def inspect
        redacted = lambda do |name, value|
          if name.match?(/_id|_key|_secret|_token$/)
            value.nil? ? "nil" : "[FILTERED]"
          else
            value
          end
        end

        inspection = instance_variables.map do |ivar|
          name = ivar.to_s.delete_prefix("@")
          value = redacted[name, instance_variable_get(ivar)]
          "#{name}: #{value}"
        end.join(", ")

        "#<#{self.class}:0x#{object_id.to_s(16)} #{inspection}>"
      end

      private

      def validate_configurations!(configs)
        configs.each do |config|
          adapter = @adapter_config.adapter_for(config)
          transport = config[:transport_type]
          # Convert string to symbol if needed
          transport = transport.to_sym if transport.is_a?(String)

          @adapter_config.validate!(
            adapter: adapter,
            transport: transport
          )
        end
      end

      def load_mcps_config
        @config_file ||= ConfigFile.new(config_path)
        @config_file.parse
      end

      def set_defaults
        # Connection configuration
        @request_timeout = REQUEST_TIMEOUT_DEFAULT

        # Connection Pool
        @max_connections = Float::INFINITY
        @pool_timeout = 5

        # Logging configuration
        @log_file = $stdout
        @log_level = ENV["RUBYLLM_MCP_DEBUG"] ? Logger::DEBUG : Logger::INFO
        @logger = nil

        # MCPs configuration
        @mcps_config_path = nil
        @mcp_configuration = []

        # Rails specific configuration
        @launch_control = :automatic

        # Roots configuration
        @roots = []

        # Protocol configuration
        @protocol_track = :stable
        @protocol_version = nil

        # Extensions configuration
        @extensions.reset!

        # OAuth configuration
        @oauth = OAuth.new

        # Sampling configuration
        @sampling.reset!
        @elicitation = Elicitation.new
        @tasks = Tasks.new

        # Event handlers
        @on_progress = nil
        @on_human_in_the_loop = nil
        @on_elicitation = nil
        @on_logging_level = nil
        @on_logging = nil
      end
    end
  end
end
