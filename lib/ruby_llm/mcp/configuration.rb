# frozen_string_literal: true

require "json"
require "yaml"
require "erb"

module RubyLLM
  module MCP
    class Configuration
      class Sampling
        attr_accessor :enabled
        attr_writer :preferred_model

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

        def enabled?
          @enabled
        end

        private

        def set_defaults
          @enabled = false
          @preferred_model = nil
          @guard = nil
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
                    :has_support_complex_parameters,
                    :roots,
                    :sampling,
                    :max_connections,
                    :pool_timeout,
                    :protocol_version,
                    :config_path,
                    :launch_control,
                    :on_logging_level

      attr_writer :logger, :mcp_configuration

      REQUEST_TIMEOUT_DEFAULT = 8000

      def initialize
        @sampling = Sampling.new
        set_defaults
      end

      def reset!
        set_defaults
      end

      def support_complex_parameters!
        return if @has_support_complex_parameters

        @has_support_complex_parameters = true
        RubyLLM::MCP.support_complex_parameters!
      end

      def logger
        @logger ||= Logger.new(
          log_file,
          progname: "RubyLLM::MCP",
          level: log_level
        )
      end

      def mcp_configuration
        @mcp_configuration + load_mcps_config
      end

      def on_progress(&block)
        @on_progress = block if block_given?
        @on_progress
      end

      def on_human_in_the_loop(&block)
        @on_human_in_the_loop = block if block_given?
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

        # Complex parameters support
        @has_support_complex_parameters = false

        # MCPs configuration
        @mcps_config_path = nil
        @mcp_configuration = []

        # Rails specific configuration
        @launch_control = :automatic

        # Roots configuration
        @roots = []

        # Sampling configuration
        @sampling.reset!

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
