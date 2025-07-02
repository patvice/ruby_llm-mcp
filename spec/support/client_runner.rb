# frozen_string_literal: true

class ClientRunner
  attr_reader :client, :options, :name

  class << self
    def build_client_runners(configs)
      @client_runners ||= {}

      configs.each do |config|
        puts config[:name]
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
    # @client.start

    @client
  end

  def stop
    @client.stop
    @client = nil
  end
end
