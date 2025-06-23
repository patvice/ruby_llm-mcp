# frozen_string_literal: true

require "logger"

module RubyLLM
  module MCP
    class Coordinator
      PROTOCOL_VERSION = "2025-03-26"
      PV_2024_11_05 = "2024-11-05"

      attr_reader :client, :transport_type, :config, :request_timeout, :headers, :transport, :initialize_response,
                  :capabilities, :protocol_version, :handle_progress

      def initialize(client, transport_type:, config: {})
        @client = client
        @transport_type = transport_type
        @config = config

        @handle_progress = config[:handle_progress]

        @protocol_version = PROTOCOL_VERSION
        @headers = config[:headers] || {}

        @transport = nil
        @capabilities = nil
      end

      def request(body, **options)
        @transport.request(body, **options)
      rescue RubyLLM::MCP::Errors::TimeoutError => e
        if @transport.alive?
          cancelation_notification(reason: "Request timed out", request_id: e.request_id)
        end
        raise e
      end

      def start_transport
        build_transport

        initialize_response = initialize_request
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

      def ping?
        ping_request = RubyLLM::MCP::Requests::Ping.new(self)
        if alive?
          result = ping_request.call
        else
          build_transport

          result = ping_request.call
          @transport = nil
        end

        result.error?
      rescue RubyLLM::MCP::Errors::TimeoutError
        false
      end

      def process_notification(result)
        notification = result.nofitication

        case type
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

      def cancelation_notification(**args)
        RubyLLM::MCP::Requests::CancelationNotification.new(self, **args).call
      end

      def ping_response
        RubyLLM::MCP::Requests::PingResponse.new(self).call
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

      private

      def process_logging_message(notification)
        level = notification.params["level"]
        logger = notification.params["logger"]
        message = notification.params["data"]

        message = ":MCP: #{logger}: #{message}"

        case level
        when "debug"
          RubyLLM.logger.debug(message["message"])
        when "info", "notice"
          RubyLLM.logger.info(message["message"])
        when "warning"
          RubyLLM.logger.warn(message["message"])
        when "error", "critical"
          RubyLLM.logger.error(message["message"])
        when "alert", "emergency"
          RubyLLM.logger.fatal(message["message"])
        end
      end

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
