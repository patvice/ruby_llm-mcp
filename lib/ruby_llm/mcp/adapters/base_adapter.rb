# frozen_string_literal: true

module RubyLLM
  module MCP
    module Adapters
      class BaseAdapter
        class << self
          def supported_features
            @supported_features ||= {}
          end

          def supports(*features)
            features.each { |f| supported_features[f] = true }
          end

          def support?(feature)
            supported_features[feature] || false
          end

          def supported_transports
            @supported_transports ||= []
          end

          def supports_transport(*transports)
            @supported_transports = transports
          end

          def transport_supported?(transport)
            supported_transports.include?(transport.to_sym)
          end
        end

        attr_reader :client

        def initialize(client, transport_type:, config: {})
          @client = client
          @transport_type = transport_type
          @config = config
        end

        # Instance methods
        def supports?(feature)
          self.class.support?(feature)
        end

        def validate_transport!(transport_type)
          unless self.class.transport_supported?(transport_type)
            raise Errors::UnsupportedTransport.new(
              message: <<~MSG.strip
                Transport '#{transport_type}' is not supported by #{self.class.name}.
                Supported transports: #{self.class.supported_transports.join(', ')}
              MSG
            )
          end
        end

        # Lifecycle methods
        def start
          raise NotImplementedError, "#{self.class.name} must implement #start"
        end

        def stop
          raise NotImplementedError, "#{self.class.name} must implement #stop"
        end

        def restart!
          raise NotImplementedError, "#{self.class.name} must implement #restart!"
        end

        def alive?
          raise NotImplementedError, "#{self.class.name} must implement #alive?"
        end

        def ping
          raise NotImplementedError, "#{self.class.name} must implement #ping"
        end

        # Capabilities
        def capabilities
          raise NotImplementedError, "#{self.class.name} must implement #capabilities"
        end

        def client_capabilities
          raise NotImplementedError, "#{self.class.name} must implement #client_capabilities"
        end

        # Core MCP methods - Tools
        def tool_list(cursor: nil)
          raise NotImplementedError, "#{self.class.name} must implement #tool_list"
        end

        def execute_tool(name:, parameters:)
          raise NotImplementedError, "#{self.class.name} must implement #execute_tool"
        end

        # Core MCP methods - Resources
        def resource_list(cursor: nil)
          raise NotImplementedError, "#{self.class.name} must implement #resource_list"
        end

        def resource_read(uri:)
          raise NotImplementedError, "#{self.class.name} must implement #resource_read"
        end

        # Core MCP methods - Prompts
        def prompt_list(cursor: nil)
          raise NotImplementedError, "#{self.class.name} must implement #prompt_list"
        end

        def execute_prompt(name:, arguments:)
          raise NotImplementedError, "#{self.class.name} must implement #execute_prompt"
        end

        # Optional features - Resource Templates
        def resource_template_list(cursor: nil) # rubocop:disable Lint/UnusedMethodArgument
          raise_unsupported_feature(:resource_templates)
        end

        # Optional features - Completions
        def completion_resource(uri:, argument:, value:, context: nil) # rubocop:disable Lint/UnusedMethodArgument
          raise_unsupported_feature(:completions)
        end

        def completion_prompt(name:, argument:, value:, context: nil) # rubocop:disable Lint/UnusedMethodArgument
          raise_unsupported_feature(:completions)
        end

        # Optional features - Logging
        def set_logging(level:) # rubocop:disable Lint/UnusedMethodArgument
          raise_unsupported_feature(:logging)
        end

        # Optional features - Subscriptions
        def resources_subscribe(uri:) # rubocop:disable Lint/UnusedMethodArgument
          raise_unsupported_feature(:subscriptions)
        end

        # Optional features - Notifications
        def initialize_notification
          raise_unsupported_feature(:notifications)
        end

        def cancelled_notification(reason:, request_id:) # rubocop:disable Lint/UnusedMethodArgument
          raise_unsupported_feature(:notifications)
        end

        def roots_list_change_notification
          raise_unsupported_feature(:notifications)
        end

        # Optional features - Responses
        def ping_response(id:) # rubocop:disable Lint/UnusedMethodArgument
          raise_unsupported_feature(:responses)
        end

        def roots_list_response(id:) # rubocop:disable Lint/UnusedMethodArgument
          raise_unsupported_feature(:responses)
        end

        def sampling_create_message_response(id:, model:, message:, **_options) # rubocop:disable Lint/UnusedMethodArgument
          raise_unsupported_feature(:sampling)
        end

        def error_response(id:, message:, code: -32_000) # rubocop:disable Lint/UnusedMethodArgument
          raise_unsupported_feature(:responses)
        end

        def elicitation_response(id:, elicitation:) # rubocop:disable Lint/UnusedMethodArgument
          raise_unsupported_feature(:elicitation)
        end

        # Helper for resource registration
        def register_resource(_resource)
          raise_unsupported_feature(:resource_registration)
        end

        private

        def raise_unsupported_feature(feature)
          raise Errors::UnsupportedFeature.new(
            message: <<~MSG.strip
              Feature '#{feature}' is not supported by #{self.class.name}.

              This feature requires the :ruby_llm adapter.
              Change your configuration to use adapter: :ruby_llm
            MSG
          )
        end
      end
    end
  end
end
