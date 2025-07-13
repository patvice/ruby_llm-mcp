# frozen_string_literal: true

require "logger"

module RubyLLM
  module MCP
    class Coordinator
      attr_reader :client, :transport_type, :config, :capabilities, :protocol_version

      def initialize(client, transport_type:, config: {})
        @client = client
        @transport_type = transport_type
        @config = config

        @protocol_version = MCP::Protocol.default_negotiated_version

        @transport = nil
        @capabilities = nil
      end

      def name
        client.name
      end

      def request(body, **options)
        transport.request(body, **options)
      rescue RubyLLM::MCP::Errors::TimeoutError => e
        if transport&.alive? && !e.request_id.nil?
          cancelled_notification(reason: "Request timed out", request_id: e.request_id)
        end
        raise e
      end

      def process_result(result)
        if result.notification?
          process_notification(result)
          return nil
        end

        if result.request?
          process_request(result) if alive?
          return nil
        end

        if result.response?
          return result
        end

        nil
      end

      def start_transport
        return unless capabilities.nil?

        transport.start

        initialize_response = initialize_request
        initialize_response.raise_error! if initialize_response.error?

        # Extract and store the negotiated protocol version
        negotiated_version = initialize_response.value["protocolVersion"]

        if negotiated_version && !MCP::Protocol.supported_version?(negotiated_version)
          raise Errors::UnsupportedProtocolVersion.new(
            message: <<~MESSAGE
              Unsupported protocol version, and could not negotiate a supported version: #{negotiated_version}.
              Supported versions: #{MCP::Protocol.supported_versions.join(', ')}
            MESSAGE
          )
        end

        @protocol_version = negotiated_version if negotiated_version

        # Set the protocol version on the transport for subsequent requests
        if @transport.respond_to?(:set_protocol_version)
          @transport.set_protocol_version(@protocol_version)
        end

        @capabilities = RubyLLM::MCP::ServerCapabilities.new(initialize_response.value["capabilities"])
        initialize_notification

        if client.logging_handler_enabled?
          set_logging(level: client.on_logging_level)
        end
      end

      def stop_transport
        @transport&.close
        @capabilities = nil
        @transport = nil
        @protocol_version = MCP::Protocol.default_negotiated_version
      end

      def restart_transport
        @initialize_response = nil
        stop_transport
        start_transport
      end

      def alive?
        !!@transport&.alive?
      end

      def ping
        ping_request = RubyLLM::MCP::Requests::Ping.new(self)
        if alive?
          result = ping_request.call
        else
          transport.start

          result = ping_request.call
          @transport = nil
        end

        result.value == {}
      rescue RubyLLM::MCP::Errors::TimeoutError, RubyLLM::MCP::Errors::TransportError
        false
      end

      def process_notification(result)
        notification = result.notification
        NotificationHandler.new(self).execute(notification)
      end

      def process_request(result)
        ResponseHandler.new(self).execute(result)
      end

      def initialize_request
        RubyLLM::MCP::Requests::Initialization.new(self).call
      end

      def tool_list(cursor: nil)
        result = RubyLLM::MCP::Requests::ToolList.new(self, cursor: cursor).call
        result.raise_error! if result.error?

        if result.next_cursor?
          result.value["tools"] + tool_list(cursor: result.next_cursor)
        else
          result.value["tools"]
        end
      end

      def execute_tool(**args)
        if client.human_in_the_loop?
          name = args[:name]
          params = args[:parameters]
          unless client.on[:human_in_the_loop].call(name, params)
            result = Result.new(
              {
                "result" => {
                  "isError" => true,
                  "content" => [{ "type" => "text", "text" => "Tool call was cancelled by the client" }]
                }
              }
            )
            return result
          end
        end

        RubyLLM::MCP::Requests::ToolCall.new(self, **args).call
      end

      def register_resource(resource)
        @client.linked_resources << resource
        @client.resources[resource.name] = resource
      end

      def resource_list(cursor: nil)
        result = RubyLLM::MCP::Requests::ResourceList.new(self, cursor: cursor).call
        result.raise_error! if result.error?

        if result.next_cursor?
          result.value["resources"] + resource_list(cursor: result.next_cursor)
        else
          result.value["resources"]
        end
      end

      def resource_read(**args)
        RubyLLM::MCP::Requests::ResourceRead.new(self, **args).call
      end

      def resource_template_list(cursor: nil)
        result = RubyLLM::MCP::Requests::ResourceTemplateList.new(self, cursor: cursor).call
        result.raise_error! if result.error?

        if result.next_cursor?
          result.value["resourceTemplates"] + resource_template_list(cursor: result.next_cursor)
        else
          result.value["resourceTemplates"]
        end
      end

      def resources_subscribe(**args)
        RubyLLM::MCP::Requests::ResourcesSubscribe.new(self, **args).call
      end

      def prompt_list(cursor: nil)
        result = RubyLLM::MCP::Requests::PromptList.new(self, cursor: cursor).call
        result.raise_error! if result.error?

        if result.next_cursor?
          result.value["prompts"] + prompt_list(cursor: result.next_cursor)
        else
          result.value["prompts"]
        end
      end

      def execute_prompt(**args)
        RubyLLM::MCP::Requests::PromptCall.new(self, **args).call
      end

      def completion_resource(**args)
        RubyLLM::MCP::Requests::CompletionResource.new(self, **args).call
      end

      def completion_prompt(**args)
        RubyLLM::MCP::Requests::CompletionPrompt.new(self, **args).call
      end

      def set_logging(**args)
        RubyLLM::MCP::Requests::LoggingSetLevel.new(self, **args).call
      end

      ## Notifications
      #
      def initialize_notification
        RubyLLM::MCP::Notifications::Initialize.new(self).call
      end

      def cancelled_notification(**args)
        RubyLLM::MCP::Notifications::Cancelled.new(self, **args).call
      end

      def roots_list_change_notification
        RubyLLM::MCP::Notifications::RootsListChange.new(self).call
      end

      ## Responses
      #
      def ping_response(**args)
        RubyLLM::MCP::Responses::Ping.new(self, **args).call
      end

      def roots_list_response(**args)
        RubyLLM::MCP::Responses::RootsList.new(self, **args).call
      end

      def sampling_create_message_response(**args)
        RubyLLM::MCP::Responses::SamplingCreateMessage.new(self, **args).call
      end

      def error_response(**args)
        RubyLLM::MCP::Responses::Error.new(self, **args).call
      end

      def elicitation_response(**args)
        RubyLLM::MCP::Responses::Elicitation.new(self, **args).call
      end

      def client_capabilities
        capabilities = {}

        if client.roots.active?
          capabilities[:roots] = {
            listChanged: true
          }
        end

        if sampling_enabled?
          capabilities[:sampling] = {}
        end

        if client.elicitation_enabled?
          capabilities[:elicitation] = {}
        end

        capabilities
      end

      def transport
        @transport ||= RubyLLM::MCP::Transport.new(@transport_type, self, config: @config)
      end

      private

      def sampling_enabled?
        MCP.config.sampling.enabled?
      end
    end
  end
end
