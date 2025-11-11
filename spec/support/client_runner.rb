# frozen_string_literal: true

class ClientRunner
  attr_reader :client, :options, :name

  class << self
    def mcp_sdk_available?
      @mcp_sdk_available ||= begin
        require "mcp"
        true
      rescue LoadError
        false
      end
    end

    def build_client_runners(configs)
      @client_runners ||= {}

      configs.each do |config|
        # Skip MCP SDK clients if the gem is not installed
        if config[:adapter] == :mcp_sdk && !mcp_sdk_available?
          puts "Skipping #{config[:name]} - MCP SDK gem not installed"
          next
        end

        @client_runners[config[:name]] = ClientRunner.new(config[:name], config[:options])
      end
    end

    def client_runners
      @client_runners ||= {}
    end

    def fetch_client(name)
      client_runners[name].client
    end

    def start_all
      @client_runners.each_value(&:start)
    end

    def stop_all
      @client_runners.each_value(&:stop)
    end
  end

  def initialize(name, options = {})
    @name = name
    @options = options
    @client = nil
  end

  def start
    return @client unless @client.nil?

    @client = RubyLLM::MCP::Client.new(**@options)
    @client.start

    @client
  end

  def stop
    @client.stop
    @client = nil
  end
end
