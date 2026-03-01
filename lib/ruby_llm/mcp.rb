# frozen_string_literal: true

# Standard Libraries
require "cgi"
require "date"
require "erb"
require "json"
require "logger"
require "open3"
require "rbconfig"
require "securerandom"
require "socket"
require "timeout"
require "uri"
require "yaml"

# Gems
require "httpx"
require "json-schema"
require "ruby_llm"
require "zeitwerk"

require_relative "chat"

module RubyLLM
  module MCP
    module_function

    TOOLSET_OPTION_MAPPINGS = {
      from_clients: %i[clients client_names],
      include_tools: %i[include_tools include],
      exclude_tools: %i[exclude_tools exclude]
    }.freeze

    def clients(config = RubyLLM::MCP.config.mcp_configuration)
      if @clients.nil?
        @clients = {}
        config.map do |options|
          @clients[options[:name]] ||= Client.new(**options)
        end
      end
      @clients
    end

    def add_client(options)
      clients[options[:name]] ||= Client.new(**options)
    end

    def remove_client(name)
      client = clients.delete(name)
      client&.stop
      client
    end

    def client(...)
      Client.new(...)
    end

    def establish_connection(&)
      clients.each_value(&:start)
      if block_given?
        begin
          yield clients
        ensure
          close_connection
        end
      else
        clients
      end
    end

    def close_connection
      clients.each_value do |client|
        client.stop if client.alive?
      end
    end

    def tools(blacklist: [], whitelist: [])
      tools = clients.values.map(&:tools)
                     .flatten
                     .reject { |tool| blacklist.include?(tool.name) }

      tools = tools.select { |tool| whitelist.include?(tool.name) } if whitelist.any?
      tools.uniq(&:name)
    end

    def toolset(name, options = nil)
      toolset_name = name.to_sym
      @toolsets ||= {}
      configured_toolset = (@toolsets[toolset_name] ||= Toolset.new(name: toolset_name))

      if block_given?
        unless options.nil?
          raise ArgumentError, "Provide either configuration options or a block, not both"
        end

        yield configured_toolset
        return configured_toolset
      end

      return configured_toolset unless options

      apply_toolset_options(configured_toolset, options)
    end

    def toolsets
      configured_toolsets = @toolsets || {}
      configured_toolsets.dup
    end

    def mcp_configurations
      config.mcp_configuration.each_with_object({}) do |config, acc|
        acc[config[:name]] = config
      end
    end

    def configure
      yield config
    end

    def config
      @config ||= Configuration.new
    end

    alias configuration config
    module_function :configuration

    def logger
      config.logger
    end

    def apply_toolset_options(toolset, options)
      config = options.dup.transform_keys(&:to_sym)

      TOOLSET_OPTION_MAPPINGS.each do |method_name, keys|
        next unless keys.any? { |key| config[key] }

        values = keys.flat_map { |key| Array(config[key]) }
        toolset.public_send(method_name, *values)
      end

      toolset
    end
    private_class_method :apply_toolset_options
  end
end

loader = Zeitwerk::Loader.for_gem_extension(RubyLLM)

loader.ignore("#{__dir__}/mcp/railtie.rb")

loader.inflector.inflect("mcp" => "MCP")
loader.inflector.inflect("sse" => "SSE")
loader.inflector.inflect("openai" => "OpenAI")
loader.inflector.inflect("streamable_http" => "StreamableHTTP")
loader.inflector.inflect("http_client" => "HTTPClient")
loader.inflector.inflect("http_server" => "HttpServer")

loader.inflector.inflect("ruby_llm_adapter" => "RubyLLMAdapter")
loader.inflector.inflect("mcp_sdk_adapter" => "MCPSdkAdapter")
loader.inflector.inflect("mcp_transports" => "MCPTransports")

loader.inflector.inflect("oauth_provider" => "OAuthProvider")
loader.inflector.inflect("browser_oauth_provider" => "BrowserOAuthProvider")

loader.setup

if defined?(Rails::Railtie)
  require_relative "mcp/railtie"
end
