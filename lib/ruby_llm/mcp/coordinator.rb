# frozen_string_literal: true

require "logger"

module RubyLLM
  module MCP
    class Coordinator
      PROTOCOL_VERSION = "2025-03-26"
      PV_2024_11_05 = "2024-11-05"

      attr_reader :client, :transport_type, :config, :request_timeout, :headers, :transport, :initialize_response,
                  :capabilities, :protocol_version

      def initialize(client, transport_type:, config: {})
        @client = client
        @transport_type = transport_type
        @config = config

        @protocol_version = PROTOCOL_VERSION
        @headers = config[:headers] || {}

        @transport = nil
        @capabilities = nil
      end

      def name
        client.name
      end

      def request(body, **options)
        @transport.request(body, **options)
      rescue RubyLLM::MCP::Errors::TimeoutError => e
        if @transport.alive?
          cancelled_notification(reason: "Request timed out", request_id: e.request_id)
        end
        raise e
      end

      def start_transport
        build_transport

        initialize_response = initialize_request
        initialize_response.raise_error! if initialize_response.error?

        # Extract and store the negotiated protocol version
        negotiated_version = initialize_response.value["protocolVersion"]
        @protocol_version = negotiated_version if negotiated_version

        # Set the protocol version on the transport for subsequent requests
        if @transport.respond_to?(:set_protocol_version)
          @transport.set_protocol_version(@protocol_version)
        end

        @capabilities = RubyLLM::MCP::Capabilities.new(initialize_response.value["capabilities"])
        initialize_notification
      end

      def stop_transport
        @transport&.close
        @transport = nil
      end

      def restart_transport
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
          build_transport

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

      def tool_list
        result = RubyLLM::MCP::Requests::ToolList.new(self).call
        result.raise_error! if result.error?

        result.value["tools"]
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

      def resource_list
        result = RubyLLM::MCP::Requests::ResourceList.new(self).call
        result.raise_error! if result.error?

        result.value["resources"]
      end

      def resource_read(**args)
        RubyLLM::MCP::Requests::ResourceRead.new(self, **args).call
      end

      def resource_template_list
        result = RubyLLM::MCP::Requests::ResourceTemplateList.new(self).call
        result.raise_error! if result.error?

        result.value["resourceTemplates"]
      end

      def resources_subscribe(**args)
        RubyLLM::MCP::Requests::ResourcesSubscribe.new(self, **args).call
      end

      def prompt_list
        result = RubyLLM::MCP::Requests::PromptList.new(self).call
        result.raise_error! if result.error?

        result.value["prompts"]
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

        capabilities
      end

      def build_transport
        case @transport_type
        when :sse
          @transport = RubyLLM::MCP::Transport::SSE.new(@config[:url],
                                                        request_timeout: @config[:request_timeout],
                                                        headers: @headers,
                                                        coordinator: self)
        when :stdio
          @transport = RubyLLM::MCP::Transport::Stdio.new(@config[:command],
                                                          request_timeout: @config[:request_timeout],
                                                          args: @config[:args],
                                                          env: @config[:env],
                                                          coordinator: self)
        when :streamable
          @transport = RubyLLM::MCP::Transport::StreamableHTTP.new(@config[:url],
                                                                   request_timeout: @config[:request_timeout],
                                                                   headers: @headers,
                                                                   coordinator: self)
        else
          message = "Invalid transport type: :#{transport_type}. Supported types are :sse, :stdio, :streamable"
          raise Errors::InvalidTransportType.new(message: message)
        end
      end

      private

      def sampling_enabled?
        MCP.config.sampling.enabled?
      end
    end
  end
end
