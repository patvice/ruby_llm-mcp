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

        # Store OAuth config for later use
        @oauth_config = config[:oauth] || config["oauth"]
        @oauth_provider = nil
        @oauth_storage = nil

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

      def_delegators :@adapter, :alive?, :capabilities, :ping, :client_capabilities,
                     :register_in_flight_request, :unregister_in_flight_request,
                     :cancel_in_flight_request

      def start
        @adapter.start
      end

      def stop
        @adapter.stop
      end

      def restart!
        @adapter.restart!
      end

      # Get or create OAuth provider for this client
      # @param type [Symbol] OAuth provider type (:standard or :browser, defaults to :standard)
      # @param options [Hash] additional options passed to provider
      # @return [OAuthProvider, BrowserOAuthProvider] OAuth provider instance
      def oauth(type: :standard, **options)
        # Return existing provider if already created
        return @oauth_provider if @oauth_provider

        # Get provider from transport if it already exists
        transport_oauth = transport_oauth_provider
        return transport_oauth if transport_oauth

        # Create new provider lazily
        server_url = @config[:url] || @config["url"]
        unless server_url
          raise Errors::ConfigurationError.new(
            message: "Cannot create OAuth provider without server URL in config"
          )
        end

        oauth_options = {
          server_url: server_url,
          scope: @oauth_config&.dig(:scope) || @oauth_config&.dig("scope"),
          storage: oauth_storage,
          **options
        }

        @oauth_provider = Auth.create_oauth(
          server_url,
          type: type,
          **oauth_options
        )
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

      def on_human_in_the_loop(handler_class = nil, **options)
        require_feature!(:human_in_the_loop)

        if block_given?
          raise ArgumentError, "Block-based human-in-the-loop callbacks are no longer supported. Use a handler class."
        end

        if handler_class
          # Validate handler class
          validate_handler_class!(handler_class, :execute)

          @on[:human_in_the_loop] = { class: handler_class, options: options }
        else
          # Clear handler when called without arguments
          @on[:human_in_the_loop] = nil
        end

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

      def on_sampling(handler_class = nil, **options, &block)
        require_feature!(:sampling)

        if handler_class
          # Validate handler class
          validate_handler_class!(handler_class, :execute)

          # Handler class provided
          @on[:sampling] = if options.any?
                             lambda do |sample|
                               handler_class.new(sample: sample, coordinator: @adapter.native_client, **options).call
                             end
                           else
                             handler_class
                           end
        elsif block_given?
          # Block provided (backward compatible)
          @on[:sampling] = block
        else
          # Clear handler when called without arguments
          @on[:sampling] = nil
        end

        self
      end

      def elicitation_enabled?
        @on.key?(:elicitation) && !@on[:elicitation].nil?
      end

      def on_elicitation(handler_class = nil, **options, &block)
        require_feature!(:elicitation)

        if handler_class
          # Validate handler class
          validate_handler_class!(handler_class, :execute)

          # Handler class provided
          @on[:elicitation] = if options.any?
                                lambda do |elicitation|
                                  handler_class.new(
                                    elicitation: elicitation,
                                    coordinator: @adapter.native_client,
                                    **options
                                  ).call
                                end
                              else
                                handler_class
                              end
        elsif block_given?
          # Block provided (backward compatible)
          @on[:elicitation] = block
        else
          # Clear handler when called without arguments
          @on[:elicitation] = nil
        end

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

      # Get OAuth provider from adapter's transport if available
      # @return [OAuthProvider, BrowserOAuthProvider, nil] OAuth provider or nil
      def transport_oauth_provider
        return nil unless @adapter

        # For RubyLLMAdapter
        if @adapter.respond_to?(:native_client)
          transport = @adapter.native_client.transport
          transport_protocol = transport.transport_protocol
          return transport_protocol.oauth_provider if transport_protocol.respond_to?(:oauth_provider)
        end

        # For MCPSdkAdapter with wrapped transports
        if @adapter.respond_to?(:mcp_client) && @adapter.instance_variable_get(:@mcp_client)
          mcp_client = @adapter.instance_variable_get(:@mcp_client)
          if mcp_client&.transport.respond_to?(:native_transport)
            return mcp_client.transport.native_transport.oauth_provider
          end
        end

        nil
      end

      def build_adapter
        case @adapter_type
        when :ruby_llm
          RubyLLM::MCP::Adapters::RubyLLMAdapter.new(self,
                                                     transport_type: @transport_type,
                                                     config: @config)
        when :mcp_sdk
          RubyLLM::MCP::Adapters::MCPSdkAdapter.new(self,
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

      # Get or create OAuth storage shared with transport
      def oauth_storage
        # Try to get storage from transport's OAuth provider
        transport_oauth = transport_oauth_provider
        return transport_oauth.storage if transport_oauth

        # Create new storage shared with client
        @oauth_storage ||= Auth::MemoryStorage.new
      end

      # Validate that a handler class has required methods
      # @param handler_class [Class] the handler class to validate
      # @param required_method [Symbol] the method that must be defined
      # @raise [ArgumentError] if validation fails
      def validate_handler_class!(handler_class, required_method)
        unless Handlers.handler_class?(handler_class)
          raise ArgumentError, "Handler must be a class, got #{handler_class.class}"
        end

        unless handler_class.method_defined?(required_method)
          raise ArgumentError, "Handler class #{handler_class} must define ##{required_method} method"
        end
      end
    end
  end
end
