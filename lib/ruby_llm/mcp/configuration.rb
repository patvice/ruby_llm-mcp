# frozen_string_literal: true

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

      attr_accessor :request_timeout, :log_file, :log_level, :has_support_complex_parameters, :roots, :sampling
      attr_writer :logger

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

      def set_defaults
        # Connection configuration
        @request_timeout = REQUEST_TIMEOUT_DEFAULT

        # Logging configuration
        @log_file = $stdout
        @log_level = ENV["RUBYLLM_MCP_DEBUG"] ? Logger::DEBUG : Logger::INFO
        @has_support_complex_parameters = false
        @logger = nil
        @roots = []

        @sampling.reset!
      end
    end
  end
end
