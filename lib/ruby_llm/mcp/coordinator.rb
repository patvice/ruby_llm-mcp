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

        case notification.type
        when "notifications/tools/list_changed"
          client.reset_tools!
        when "notifications/resources/list_changed"
          client.reset_resources!
        when "notifications/resources/updated"
          uri = notification.params["uri"]
          resource = client.resources.find { |r| r.uri == uri }
          resource&.reset_content!
        when "notifications/prompts/list_changed"
          client.reset_prompts!
        when "notifications/message"
          process_logging_message(notification)
        when "notifications/progress"
          process_progress_message(notification)
        when "notifications/cancelled"
          # TODO: - do nothing at the moment until we support client operations
        else
          message = "Unknown notification type: #{notification.type} params:#{notification.params.to_h}"
          raise Errors::UnknownNotification.new(message: message)
        end
      end

      def process_request(result)
        if result.ping?
          ping_response(id: result.id)
          return
        end

        # Handle server-initiated requests
        # Currently, we do not support any client operations but will
        raise RubyLLM::MCP::Errors::UnknownRequest.new(message: "Unknown request type: #{result.inspect}")
      end

      def initialize_request
        RubyLLM::MCP::Requests::Initialization.new(self).call
      end

      def tool_list(cursor: nil)
        result = RubyLLM::MCP::Requests::ToolList.new(self, cursor: cursor).call
        result.raise_error! if result.error?

        if result.next_cursor?
          result.value["tools"] + tool_list(next_cursor: result.next_cursor)
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

      def resource_list(cursor: nil)
        result = RubyLLM::MCP::Requests::ResourceList.new(self, cursor: cursor).call
        result.raise_error! if result.error?

        if result.next_cursor?
          result.value["resources"] + resource_list(next_cursor: result.next_cursor)
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
          result.value["resourceTemplates"] + resource_template_list(next_cursor: result.next_cursor)
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
          result.value["prompts"] + prompt_list(next_cursor: result.next_cursor)
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

      def initialize_notification
        RubyLLM::MCP::Requests::InitializeNotification.new(self).call
      end

      def cancelled_notification(**args)
        RubyLLM::MCP::Requests::CancelledNotification.new(self, **args).call
      end

      def ping_response(id: nil)
        RubyLLM::MCP::Requests::PingResponse.new(self, id: id).call
      end

      def set_logging(level:)
        RubyLLM::MCP::Requests::LoggingSetLevel.new(self, level: level).call
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

      def process_logging_message(notification)
        if client.logging_handler_enabled?
          client.on[:logging].call(notification)
        else
          default_process_logging_message(notification)
        end
      end

      def default_process_logging_message(notification, logger: RubyLLM::MCP.logger)
        level = notification.params["level"]
        logger_message = notification.params["logger"]
        message = notification.params["data"]

        message = "#{logger_message}: #{message}"

        case level
        when "debug"
          logger.debug(message["message"])
        when "info", "notice"
          logger.info(message["message"])
        when "warning"
          logger.warn(message["message"])
        when "error", "critical"
          logger.error(message["message"])
        when "alert", "emergency"
          logger.fatal(message["message"])
        end
      end

      def name
        client.name
      end

      private

      def process_progress_message(notification)
        progress_obj = RubyLLM::MCP::Progress.new(self, client.on[:progress], notification.params)
        if client.tracking_progress?
          progress_obj.execute_progress_handler
        end
      end
    end
  end
end
