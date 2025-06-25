# frozen_string_literal: true

require "logger"

module RubyLLM
  module MCP
    class Coordinator
      PROTOCOL_VERSION = "2025-03-26"
      PV_2024_11_05 = "2024-11-05"

      attr_reader :client, :transport_type, :config, :request_timeout, :headers, :transport, :initialize_response,
                  :capabilities, :protocol_version, :handle_progress

      def initialize(client, transport_type:, handle_progress:, config: {})
        @client = client
        @transport_type = transport_type
        @config = config

        @handle_progress = handle_progress

        @protocol_version = PROTOCOL_VERSION
        @headers = config[:headers] || {}

        @transport = nil
        @capabilities = nil
      end

      def request(body, **options)
        RubyLLM::MCP.logger.info("Request #{client.name}: body: #{body} options: #{options}")
        result = @transport.request(body, **options)
        RubyLLM::MCP.logger.info("Response #{client.name}: result: #{result}")
        result
      rescue RubyLLM::MCP::Errors::TimeoutError => e
        if @transport.alive?
          cancelled_notification(reason: "Request timed out", request_id: e.request_id)
        end
        raise e
      end

      def start_transport
        build_transport

        initialize_response = initialize_request
        puts "initialize_response: #{initialize_response.inspect}"
        initialize_response.raise_error! if initialize_response.error?

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
          uri = notification["params"]["uri"]
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
                result: {
                  isError: true,
                  error: "Tool execution was cancelled by the client"
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

      def initialize_notification
        RubyLLM::MCP::Requests::InitializeNotification.new(self).call
      end

      def cancelled_notification(**args)
        RubyLLM::MCP::Requests::CancelledNotification.new(self, **args).call
      end

      def ping_response
        RubyLLM::MCP::Requests::PingResponse.new(self).call
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
          @transport = RubyLLM::MCP::Transport::Streamable.new(@config[:url],
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
        progress_obj = Progress.new(self, @handle_progress, notification["params"])
        if progress
          progress_obj.execute_progress_handler
        else
          message = "No progress handler configured, but received progress notification. progress: #{progress_obj.to_h}"
          raise Errors::ProgressHandlerNotAvailable.new(message: message)
        end
      end
    end
  end
end
