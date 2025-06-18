# frozen_string_literal: true

module RubyLLM
  module MCP
    class Client
      PROTOCOL_VERSION = "2025-03-26"
      PV_2024_11_05 = "2024-11-05"

      attr_reader :name, :config, :transport_type, :transport, :request_timeout, :protocol_version,
                  :capabilities, :coordinator

      def initialize(name:, transport_type:, request_timeout: 8000, config: {})
        @name = name
        @config = config
        @protocol_version = PROTOCOL_VERSION

        @transport_type = transport_type.to_sym
        @coordinator = Coordinator.new(client: self, transport_type: transport_type, request_timeout: request_timeout,
                                       config: config)
      end

      def start
        @capabilities = coordinator.initialize_coordinator
      end

      def stop
        coordinator.stop!
      end

      def tools(refresh: false)
        @tools = nil if refresh
        @tools ||= fetch_and_create_tools
      end

      def resources(refresh: false)
        @resources = nil if refresh
        @resources ||= fetch_and_create_resources
      end

      def resource_templates(refresh: false)
        @resource_templates = nil if refresh
        @resource_templates ||= fetch_and_create_resources(set_as_template: true)
      end

      def prompts(refresh: false)
        @prompts = nil if refresh
        @prompts ||= fetch_and_create_prompts
      end

      def ping
        coordinator.ping
      end

      private

      def fetch_and_create_tools
        tools_response = coordinator.tool_list_request
        tools_response = tools_response["result"]["tools"]

        @tools = tools_response.map do |tool|
          RubyLLM::MCP::Tool.new(self, tool)
        end
      end

      def fetch_and_create_resources(set_as_template: false)
        resources_response = coordinator.resources_list_request
        resources_response = resources_response["result"]["resources"]

        resources = {}
        resources_response.each do |resource|
          new_resource = RubyLLM::MCP::Resource.new(self, resource, template: set_as_template)
          resources[new_resource.name] = new_resource
        end

        resources
      end

      def fetch_and_create_prompts
        prompts_response = coordinator.prompt_list_request
        prompts_response = prompts_response["result"]["prompts"]

        prompts = {}
        prompts_response.each do |prompt|
          new_prompt = RubyLLM::MCP::Prompt.new(self,
                                                name: prompt["name"],
                                                description: prompt["description"],
                                                arguments: prompt["arguments"])

          prompts[new_prompt.name] = new_prompt
        end

        prompts
      end
    end
  end
end
