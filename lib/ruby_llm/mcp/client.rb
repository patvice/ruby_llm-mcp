# frozen_string_literal: true

require "forwardable"

module RubyLLM
  module MCP
    class Client
      extend Forwardable

      attr_reader :name, :config, :transport_type, :request_timeout, :log_level, :on, :roots
      attr_accessor :linked_resources

      def initialize(name:, transport_type:, start: true, request_timeout: MCP.config.request_timeout, config: {})
        @name = name
        @with_prefix = config.delete(:with_prefix) || false
        @config = config.merge(request_timeout: request_timeout)
        @transport_type = transport_type.to_sym
        @request_timeout = request_timeout

        @coordinator = setup_coordinator

        @on = {}
        @tools = {}
        @resources = {}
        @resource_templates = {}
        @prompts = {}

        @log_level = nil

        @linked_resources = []

        setup_roots
        setup_sampling

        @coordinator.start_transport if start
      end

      def_delegators :@coordinator, :alive?, :capabilities, :ping, :client_capabilities

      def start
        @coordinator.start_transport
      end

      def stop
        @coordinator.stop_transport
      end

      def restart!
        @coordinator.restart_transport
      end

      def tools(refresh: false)
        return [] unless capabilities.tools_list?

        fetch(:tools, refresh) do
          tools = @coordinator.tool_list
          build_map(tools, MCP::Tool, with_prefix: @with_prefix)
        end

        @tools.values
      end

      def tool(name, refresh: false)
        tools(refresh: refresh)

        @tools[name]
      end

      def reset_tools!
        @tools = {}
      end

      def resources(refresh: false)
        return [] unless capabilities.resources_list?

        fetch(:resources, refresh) do
          resources = @coordinator.resource_list
          resources = build_map(resources, MCP::Resource)
          include_linked_resources(resources)
        end

        @resources.values
      end

      def resource(name, refresh: false)
        resources(refresh: refresh)

        @resources[name]
      end

      def reset_resources!
        @resources = {}
      end

      def resource_templates(refresh: false)
        return [] unless capabilities.resources_list?

        fetch(:resource_templates, refresh) do
          resource_templates = @coordinator.resource_template_list
          build_map(resource_templates, MCP::ResourceTemplate)
        end

        @resource_templates.values
      end

      def resource_template(name, refresh: false)
        resource_templates(refresh: refresh)

        @resource_templates[name]
      end

      def reset_resource_templates!
        @resource_templates = {}
      end

      def prompts(refresh: false)
        return [] unless capabilities.prompt_list?

        fetch(:prompts, refresh) do
          prompts = @coordinator.prompt_list
          build_map(prompts, MCP::Prompt)
        end

        @prompts.values
      end

      def prompt(name, refresh: false)
        prompts(refresh: refresh)

        @prompts[name]
      end

      def reset_prompts!
        @prompts = {}
      end

      def tracking_progress?
        @on.key?(:progress) && !@on[:progress].nil?
      end

      def on_progress(&block)
        @on[:progress] = block
        self
      end

      def human_in_the_loop?
        @on.key?(:human_in_the_loop) && !@on[:human_in_the_loop].nil?
      end

      def on_human_in_the_loop(&block)
        @on[:human_in_the_loop] = block
        self
      end

      def logging_handler_enabled?
        @on.key?(:logging) && !@on[:logging].nil?
      end

      def logging_enabled?
        !@log_level.nil?
      end

      def on_logging(level: Logging::WARNING, &block)
        @on_logging_level = level
        if alive?
          @coordinator.set_logging(level: level)
        end

        @on[:logging] = block
        self
      end

      def sampling_callback_enabled?
        @on.key?(:sampling) && !@on[:sampling].nil?
      end

      def on_sampling(&block)
        @on[:sampling] = block
        self
      end

      def elicitation_enabled?
        @on.key?(:elicitation) && !@on[:elicitation].nil?
      end

      def on_elicitation(&block)
        @on[:elicitation] = block
        self
      end

      def to_h
        {
          name: @name,
          transport_type: @transport_type,
          request_timeout: @request_timeout,
          start: @start,
          config: @config,
          on: @on,
          tools: @tools,
          resources: @resources,
          resource_templates: @resource_templates,
          prompts: @prompts,
          log_level: @log_level
        }
      end

      alias as_json to_h

      def inspect
        "#<#{self.class.name}:0x#{object_id.to_s(16)} #{to_h.map { |k, v| "#{k}: #{v}" }.join(', ')}>"
      end

      private

      def setup_coordinator
        Coordinator.new(self,
                        transport_type: @transport_type,
                        config: @config)
      end

      def fetch(cache_key, refresh)
        instance_variable_set("@#{cache_key}", {}) if refresh
        if instance_variable_get("@#{cache_key}").empty?
          instance_variable_set("@#{cache_key}", yield)
        end
        instance_variable_get("@#{cache_key}")
      end

      def build_map(raw_data, klass, with_prefix: false)
        raw_data.each_with_object({}) do |item, acc|
          instance = if with_prefix
                       klass.new(@coordinator, item, with_prefix: @with_prefix)
                     else
                       klass.new(@coordinator, item)
                     end
          acc[instance.name] = instance
        end
      end

      def include_linked_resources(resources)
        @linked_resources.each do |resource|
          resources[resource.name] = resource
        end

        resources
      end

      def setup_roots
        @roots = Roots.new(paths: MCP.config.roots, coordinator: @coordinator)
      end

      def setup_sampling
        @on[:sampling] = MCP.config.sampling.guard
      end

      def setup_event_handlers
        @on[:progress] = MCP.config.on_progress
        @on[:human_in_the_loop] = MCP.config.on_human_in_the_loop
        @on[:logging] = MCP.config.on_logging
        @on_logging_level = MCP.config.on_logging_level
        @on[:elicitation] = MCP.config.on_elicitation
      end
    end
  end
end
