# frozen_string_literal: true

module RubyLLM
  module MCP
    class Client
      PROTOCOL_VERSION = "2025-03-26"
      PV_2024_11_05 = "2024-11-05"

      attr_reader :name, :config, :transport_type, :transport, :request_timeout, :reverse_proxy_url, :protocol_version,
                  :capabilities

      def initialize(name:, transport_type:, request_timeout: 8000, reverse_proxy_url: nil, config: {})
        @name = name
        @config = config
        @protocol_version = PROTOCOL_VERSION
        @headers = config[:headers] || {}

        @transport_type = transport_type.to_sym

        case @transport_type
        when :sse
          @transport = RubyLLM::MCP::Transport::SSE.new(@config[:url], headers: @headers)
        when :stdio
          @transport = RubyLLM::MCP::Transport::Stdio.new(@config[:command], args: @config[:args], env: @config[:env])
        when :streamable
          @transport = RubyLLM::MCP::Transport::Streamable.new(@config[:url], headers: @headers)
        else
          raise "Invalid transport type: #{transport_type}"
        end
        @capabilities = nil

        @request_timeout = request_timeout
        @reverse_proxy_url = reverse_proxy_url

        initialize_request
        notification_request
      end

      def request(body, add_id: true, wait_for_response: true, **options)
        @transport.request(body, add_id: add_id, wait_for_response: wait_for_response, **options)
      end

      def tools(refresh: false)
        @tools = nil if refresh
        @tools ||= fetch_and_create_tools
      end

      def resources(refresh: false)
        @resources = nil if refresh
        @resources ||= fetch_and_create_resources
      end

      def execute_tool(name:, parameters:)
        response = execute_tool_request(name: name, parameters: parameters)
        result = response["result"]
        # TODO: handle tool error when "isError" is true in result
        #
        # TODO: Implement "type": "image" and "type": "resource"
        result["content"].map { |content| content["text"] }.join("\n")
      end

      def resource_read_request(uri:)
        @resource_read_response = RubyLLM::MCP::Requests::ResourceRead.new(self, uri: uri).call
      end

      private

      def initialize_request
        @initialize_response = RubyLLM::MCP::Requests::Initialization.new(self).call
        @capabilities = RubyLLM::MCP::Capabilities.new(@initialize_response["result"]["capabilities"])
      end

      def notification_request
        @notification_response = RubyLLM::MCP::Requests::Notification.new(self).call
      end

      def tool_list_request
        @tool_request = RubyLLM::MCP::Requests::ToolList.new(self).call
      end

      def execute_tool_request(name:, parameters:)
        @execute_tool_response = RubyLLM::MCP::Requests::ToolCall.new(self, name: name, parameters: parameters).call
      end

      def resources_list_request
        @resources_request = RubyLLM::MCP::Requests::ResourceList.new(self).call
      end

      def resource_template_list_request
        @resource_template_list_response = RubyLLM::MCP::Requests::ResourceTemplateList.new(self).call
      end

      def fetch_and_create_tools
        tools_response = tool_list_request
        tools_response = tools_response["result"]["tools"]

        @tools = tools_response.map do |tool|
          RubyLLM::MCP::Tool.new(self, tool)
        end
      end

      def fetch_and_create_resources
        resources_response = resources_list_request
        resources_response = resources_response["result"]["resources"]

        @resources = resources_response.map do |resource|
          RubyLLM::MCP::Resource.new(self, resource)
        end
      end
    end
  end
end
