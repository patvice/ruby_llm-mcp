# frozen_string_literal: true

require "forwardable"

module RubyLLM
  module MCP
    class Client
      extend Forwardable

      attr_reader :name, :config, :transport_type, :request_timeout, :log_level, :on, :roots, :adapter,
                  :on_logging_level
      attr_accessor :linked_resources

      def initialize(name:, transport_type:, sdk: nil, adapter: nil, start: true, # rubocop:disable Metrics/ParameterLists
                     request_timeout: MCP.config.request_timeout, config: {})
        @name = name
        @transport_type = transport_type.to_sym
        @adapter_type = adapter || sdk || MCP.config.default_adapter

        # Validate early
        MCP.config.adapter_config.validate!(
          adapter: @adapter_type,
          transport: @transport_type
        )

        @with_prefix = config.delete(:with_prefix) || false
        @config = config.merge(request_timeout: request_timeout)
        @request_timeout = request_timeout

        @on = {}
        @tools = {}
        @resources = {}
        @resource_templates = {}
        @prompts = {}

        @log_level = nil

        @linked_resources = []

        # Build adapter based on configuration
        @adapter = build_adapter

        setup_roots if @adapter.supports?(:roots)
        setup_sampling if @adapter.supports?(:sampling)
        setup_event_handlers

        @adapter.start if start
      end

      def_delegators :@adapter, :alive?, :capabilities, :ping, :client_capabilities

      def start
        @adapter.start
      end

      def stop
        @adapter.stop
      end

      def restart!
        @adapter.restart!
      end

      def tools(refresh: false)
        require_feature!(:tools)
        return [] unless capabilities.tools_list?

        fetch(:tools, refresh) do
          tools = @adapter.tool_list
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
        require_feature!(:resources)
        return [] unless capabilities.resources_list?

        fetch(:resources, refresh) do
          resources = @adapter.resource_list
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
        require_feature!(:resource_templates)
        return [] unless capabilities.resources_list?

        fetch(:resource_templates, refresh) do
          resource_templates = @adapter.resource_template_list
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
        require_feature!(:prompts)
        return [] unless capabilities.prompt_list?

        fetch(:prompts, refresh) do
          prompts = @adapter.prompt_list
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
        require_feature!(:progress_tracking)
        if alive?
          @adapter.set_progress_tracking(enabled: true)
        end

        @on[:progress] = block
        self
      end

      def human_in_the_loop?
        @on.key?(:human_in_the_loop) && !@on[:human_in_the_loop].nil?
      end

      def on_human_in_the_loop(&block)
        require_feature!(:human_in_the_loop)
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
        require_feature!(:logging)
        @on_logging_level = level
        if alive?
          @adapter.set_logging(level: level)
        end

        @on[:logging] = block
        self
      end

      def sampling_callback_enabled?
        @on.key?(:sampling) && !@on[:sampling].nil?
      end

      def on_sampling(&block)
        require_feature!(:sampling)
        @on[:sampling] = block
        self
      end

      def elicitation_enabled?
        @on.key?(:elicitation) && !@on[:elicitation].nil?
      end

      def on_elicitation(&block)
        require_feature!(:elicitation)
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

      def build_adapter
        case @adapter_type
        when :ruby_llm
          RubyLLM::MCP::Adapters::RubyLLMAdapter.new(self,
                                                     transport_type: @transport_type,
                                                     config: @config)
        when :mcp_sdk
          RubyLLM::MCP::Adapters::MCPSDKAdapter.new(self,
                                                    transport_type: @transport_type,
                                                    config: @config)
        else
          raise ArgumentError, "Unknown adapter type: #{@adapter_type}"
        end
      end

      def require_feature!(feature)
        unless @adapter.supports?(feature)
          raise Errors::UnsupportedFeature.new(
            message: <<~MSG.strip
              Feature '#{feature}' is not supported by the #{@adapter_type} adapter.

              This feature requires the :ruby_llm adapter.
              Change your configuration to use adapter: :ruby_llm
            MSG
          )
        end
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
                       klass.new(@adapter, item, with_prefix: @with_prefix)
                     else
                       klass.new(@adapter, item)
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
        @roots = Roots.new(paths: MCP.config.roots, adapter: @adapter)
      end

      def setup_sampling
        @on[:sampling] = MCP.config.sampling.guard
      end

      def setup_event_handlers
        # Only setup handlers that are supported
        if @adapter.supports?(:progress_tracking)
          @on[:progress] = MCP.config.on_progress
          if @on[:progress] && alive?
            @adapter.set_progress_tracking(enabled: true)
          end
        end

        if @adapter.supports?(:human_in_the_loop)
          @on[:human_in_the_loop] = MCP.config.on_human_in_the_loop
        end

        if @adapter.supports?(:logging)
          @on[:logging] = MCP.config.on_logging
          @on_logging_level = MCP.config.on_logging_level
        end

        if @adapter.supports?(:elicitation)
          @on[:elicitation] = MCP.config.on_elicitation
        end
      end
    end
  end
end
