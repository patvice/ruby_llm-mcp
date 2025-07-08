# frozen_string_literal: true

require "ruby_llm"
require "zeitwerk"
require_relative "chat"

module RubyLLM
  module MCP
    module_function

    def clients(config = RubyLLM::MCP.config.mcp_configuration)
      @clients ||= {}
      config.map do |options|
        @clients[options[:name]] ||= Client.new(**options)
      end
      @clients
    end

    def add_client(options)
      @clients ||= {}
      @clients[options[:name]] ||= Client.new(**options)
    end

    def remove_client(name)
      @clients ||= {}
      client = @clients.delete(name)
      client&.stop
      client
    end

    def client(...)
      Client.new(...)
    end

    def establish_connection(&)
      clients.each(&:start)
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
      clients.each do |client|
        client.stop if client.alive?
      end
    end

    def tools(blacklist: [], whitelist: [])
      tools = @clients.values.map(&:tools)
                      .flatten
                      .reject { |tool| blacklist.include?(tool.name) }

      tools = tools.select { |tool| whitelist.include?(tool.name) } if whitelist.any?
      tools.uniq(&:name)
    end

    def support_complex_parameters!
      require_relative "mcp/providers/openai/complex_parameter_support"
      require_relative "mcp/providers/anthropic/complex_parameter_support"
      require_relative "mcp/providers/gemini/complex_parameter_support"
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
  end
end

require_relative "mcp/railtie" if defined?(Rails::Railtie)

loader = Zeitwerk::Loader.for_gem_extension(RubyLLM)
loader.inflector.inflect("mcp" => "MCP")
loader.inflector.inflect("sse" => "SSE")
loader.inflector.inflect("openai" => "OpenAI")
loader.inflector.inflect("streamable_http" => "StreamableHTTP")
loader.inflector.inflect("http_client" => "HTTPClient")

loader.setup
