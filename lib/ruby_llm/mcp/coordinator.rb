# frozen_string_literal: true

module RubyLLM
  module MCP
    class Coordinator
      def initialize(client:, transport_type:, request_timeout:, config:)
        @client = client
        @transport_type = transport_type
        @request_timeout = request_timeout
        @config = config
        @headers = config[:headers] || {}

        case @transport_type
        when :sse
          @transport = Transport::SSE.new(@config[:url], headers: @headers, request_timeout: @request_timeout)
        when :stdio
          @transport = Transport::Stdio.new(@config[:command], args: @config[:args], env: @config[:env],
                                                               request_timeout: @request_timeout)
        when :streamable
          @transport = Transport::Streamable.new(@config[:url], headers: @headers, request_timeout: @request_timeout)
        else
          raise "Invalid transport type: #{transport_type}"
        end
      end

      def request(body, **options)
        @transport.request(body, **options)
      end

      def initialize_coordinator
        capabilities = initialize_request
        notify_initialized_request
        capabilities
      end

      def initialize_request
        @initialize_response = RubyLLM::MCP::Requests::Initialization.new(self).call
        RubyLLM::MCP::Capabilities.new(@initialize_response["result"]["capabilities"])
      end

      def notify_initialized_request
        Requests::NotifyInitialized.new(self).call
      end

      def execute_tool(**args)
        Requests::ToolCall.new(self, **args).call
      end

      def resource_read_request(**args)
        Requests::ResourceRead.new(self, **args).call
      end

      def completion(**args)
        Requests::Completion.new(self, **args).call
      end

      def execute_prompt(**args)
        Requests::PromptCall.new(self, **args).call
      end

      def tool_list_request
        Requests::ToolList.new(self).call
      end

      def resources_list_request
        Requests::ResourceList.new(self).call
      end

      def resource_template_list_request
        Requests::ResourceTemplateList.new(self).call
      end

      def prompt_list_request
        Requests::PromptList.new(self).call
      end

      def ping
        Requests::Ping.new(self).call
        true
      rescue RubyLLM::MCP::Errors::TimeoutError
        false
      end
    end
  end
end
