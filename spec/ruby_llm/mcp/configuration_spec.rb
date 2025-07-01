# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Configuration do
  after do
    RubyLLM::MCP.config.reset!
    MCPTestConfiguration.configure!
  end

  describe "initialization" do
    it "sets default values" do
      config = RubyLLM::MCP::Configuration.new

      expect(config.request_timeout).to eq(8000)
      expect(config.log_file).to eq($stdout)
      expect(config.log_level).to eq(Logger::INFO)
      expect(config.has_support_complex_parameters).to be(false)
    end

    it "sets debug log level when RUBYLLM_MCP_DEBUG environment variable is set" do
      ENV["RUBYLLM_MCP_DEBUG"] = "true"
      config = RubyLLM::MCP::Configuration.new

      expect(config.log_level).to eq(Logger::DEBUG)

      ENV.delete("RUBYLLM_MCP_DEBUG")
    end
  end

  describe "accessors" do
    let(:config) { RubyLLM::MCP::Configuration.new }

    it "allows reading and writing request_timeout" do
      config.request_timeout = 5000
      expect(config.request_timeout).to eq(5000)
    end

    it "allows reading and writing log_file" do
      log_file = StringIO.new
      config.log_file = log_file
      expect(config.log_file).to eq(log_file)
    end

    it "allows reading and writing log_level" do
      config.log_level = Logger::ERROR
      expect(config.log_level).to eq(Logger::ERROR)
    end

    it "allows reading and writing has_support_complex_parameters" do
      config.has_support_complex_parameters = true
      expect(config.has_support_complex_parameters).to be(true)
    end

    it "allows writing logger" do
      custom_logger = Logger.new($stdout)
      config.logger = custom_logger
      expect(config.logger).to eq(custom_logger)
    end
  end

  describe "reset!" do
    it "resets all configuration to defaults" do
      config = RubyLLM::MCP.config

      # Change some values
      config.request_timeout = 5000
      config.log_level = Logger::ERROR
      config.has_support_complex_parameters = true

      # Reset
      config.reset!

      # Check defaults are restored
      expect(config.request_timeout).to eq(8000)
      expect(config.log_file).to eq($stdout)
      expect(config.log_level).to eq(Logger::INFO)
      expect(config.has_support_complex_parameters).to be(false)
    end

    it "resets logger to nil so it gets recreated" do
      config = RubyLLM::MCP.config

      # Access logger to create it
      original_logger = config.logger

      # Reset
      config.reset!

      # Logger should be recreated on next access
      new_logger = config.logger
      expect(new_logger).to be_a(Logger)
      expect(new_logger).not_to eq(original_logger)
    end
  end

  describe "logger" do
    let(:config) { RubyLLM::MCP::Configuration.new }

    it "creates a default logger with correct settings" do
      logger = config.logger

      expect(logger).to be_a(Logger)
      expect(logger.progname).to eq("RubyLLM::MCP")
      expect(logger.level).to eq(Logger::INFO)
    end

    it "creates logger with custom log_file and log_level" do
      buffer = StringIO.new
      config.log_file = buffer
      config.log_level = Logger::DEBUG

      logger = config.logger

      expect(logger).to be_a(Logger)
      expect(logger.level).to eq(Logger::DEBUG)
    end

    it "memoizes the logger instance" do
      logger1 = config.logger
      logger2 = config.logger

      expect(logger1).to eq(logger2)
    end

    it "recreates logger after reset" do
      logger1 = config.logger
      config.reset!
      logger2 = config.logger

      expect(logger1).not_to eq(logger2)
    end
  end

  describe "support_complex_parameters!" do
    it "sets has_support_complex_parameters to true" do
      config = RubyLLM::MCP::Configuration.new
      expect(config.has_support_complex_parameters).to be(false)

      config.support_complex_parameters!
      expect(config.has_support_complex_parameters).to be(true)
    end

    it "calls RubyLLM::MCP.support_complex_parameters!" do
      config = RubyLLM::MCP::Configuration.new
      allow(RubyLLM::MCP).to receive(:support_complex_parameters!)

      config.support_complex_parameters!

      expect(RubyLLM::MCP).to have_received(:support_complex_parameters!)
    end

    it "does not call RubyLLM::MCP.support_complex_parameters! if already enabled" do
      config = RubyLLM::MCP::Configuration.new
      config.support_complex_parameters!

      allow(RubyLLM::MCP).to receive(:support_complex_parameters!)

      config.support_complex_parameters!

      expect(RubyLLM::MCP).not_to have_received(:support_complex_parameters!)
    end
  end

  it "can be configured with support_complex_parameters!" do
    RubyLLM::MCP.configure(&:support_complex_parameters!)

    expect(RubyLLM::MCP.configuration.has_support_complex_parameters).to be(true)
  end

  it "can be configured with a custom logger" do
    RubyLLM::MCP.configure do |config|
      config.logger = Logger.new($stdout)
    end

    expect(RubyLLM::MCP.configuration.logger).to be_a(Logger)
  end

  describe "inspect" do
    let(:config) { RubyLLM::MCP::Configuration.new }

    it "does not share secrets if inspected" do
      RubyLLM::MCP.configure do |config|
        config.log_file = $stdout
        config.log_level = Logger::DEBUG
      end

      expect(RubyLLM::MCP.configuration.inspect).to include("log_file")
    end

    it "filters sensitive field names ending with _id" do
      config.instance_variable_set(:@client_id, "secret123")

      inspection = config.inspect
      expect(inspection).to include("client_id: [FILTERED]")
      expect(inspection).not_to include("secret123")
    end

    it "filters sensitive field names ending with _key" do
      config.instance_variable_set(:@api_key, "secret_key")

      inspection = config.inspect
      expect(inspection).to include("api_key: [FILTERED]")
      expect(inspection).not_to include("secret_key")
    end

    it "filters sensitive field names ending with _secret" do
      config.instance_variable_set(:@client_secret, "top_secret")

      inspection = config.inspect
      expect(inspection).to include("client_secret: [FILTERED]")
      expect(inspection).not_to include("top_secret")
    end

    it "filters sensitive field names ending with _token" do
      config.instance_variable_set(:@access_token, "token123")

      inspection = config.inspect
      expect(inspection).to include("access_token: [FILTERED]")
      expect(inspection).not_to include("token123")
    end

    it "shows nil values for sensitive fields as 'nil'" do
      config.instance_variable_set(:@api_key, nil)

      inspection = config.inspect
      expect(inspection).to include("api_key: nil")
    end

    it "does not filter non-sensitive field names" do
      config.request_timeout = 5000

      inspection = config.inspect
      expect(inspection).to include("request_timeout: 5000")
    end
  end

  it "enable debug mode if RUBYLLM_MCP_DEBUG is set" do
    ENV["RUBYLLM_MCP_DEBUG"] = "true"

    RubyLLM::MCP.configuration.reset!
    expect(RubyLLM::MCP.configuration.log_level).to eq(Logger::DEBUG)
    ENV.delete("RUBYLLM_MCP_DEBUG")
  end
end
