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
      expect(config.protocol_version).to eq(RubyLLM::MCP::Native::Protocol.latest_version)
    end

    it "sets debug log level when RUBYLLM_MCP_DEBUG environment variable is set" do
      ENV["RUBYLLM_MCP_DEBUG"] = "true"
      config = RubyLLM::MCP::Configuration.new

      expect(config.log_level).to eq(Logger::DEBUG)

      ENV.delete("RUBYLLM_MCP_DEBUG")
    end

    it "sets default protocol_version to latest version" do
      config = RubyLLM::MCP::Configuration.new

      expect(config.protocol_version).to eq(RubyLLM::MCP::Native::Protocol::LATEST_PROTOCOL_VERSION)
      expect(config.protocol_version).to eq("2025-06-18")
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

    it "allows reading and writing protocol_version" do
      config.protocol_version = "2024-11-05"
      expect(config.protocol_version).to eq("2024-11-05")
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
      config.protocol_version = "2024-11-05"

      # Reset
      config.reset!

      # Check defaults are restored
      expect(config.request_timeout).to eq(8000)
      expect(config.log_file).to eq($stdout)
      expect(config.log_level).to eq(Logger::INFO)
      expect(config.has_support_complex_parameters).to be(false)
      expect(config.protocol_version).to eq(RubyLLM::MCP::Native::Protocol.latest_version)
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

  describe "OAuth configuration" do
    it "has an oauth accessor" do
      config = RubyLLM::MCP::Configuration.new

      expect(config.oauth).to be_a(RubyLLM::MCP::Configuration::OAuth)
    end

    it "allows configuring OAuth settings" do
      RubyLLM::MCP.configure do |config|
        config.oauth.client_name = "My Custom App"
        config.oauth.client_uri = "https://example.com"
      end

      expect(RubyLLM::MCP.config.oauth.client_name).to eq("My Custom App")
      expect(RubyLLM::MCP.config.oauth.client_uri).to eq("https://example.com")
    end
  end

  describe "protocol_version usage in OAuth" do
    it "uses config protocol_version in OAuth provider metadata discovery" do
      RubyLLM::MCP.configure do |config|
        config.protocol_version = "2025-03-26"
      end

      # Verify the header is sent during OAuth discovery
      discovery_stub = stub_request(:get, "https://example.com/.well-known/oauth-authorization-server")
                       .with(headers: { "MCP-Protocol-Version" => "2025-03-26" })
                       .to_return(
                         status: 200,
                         body: {
                           issuer: "https://example.com",
                           authorization_endpoint: "https://example.com/authorize",
                           token_endpoint: "https://example.com/token"
                         }.to_json
                       )

      # Use a fresh storage instance to avoid caching issues
      storage = RubyLLM::MCP::Auth::MemoryStorage.new
      provider = RubyLLM::MCP::Auth::OAuthProvider.new(
        server_url: "https://example.com",
        redirect_uri: "http://localhost:8080/callback",
        storage: storage
      )

      # Access the discoverer and trigger discovery
      discoverer = provider.instance_variable_get(:@discoverer)
      discoverer.discover("https://example.com")
      expect(discovery_stub).to have_been_requested
    end

    it "uses latest version by default in OAuth provider metadata discovery" do
      RubyLLM::MCP.config.reset!

      # Verify the default header is sent during OAuth discovery
      discovery_stub = stub_request(:get, "https://example.com/.well-known/oauth-authorization-server")
                       .with(headers: { "MCP-Protocol-Version" => RubyLLM::MCP::Native::Protocol.latest_version })
                       .to_return(
                         status: 200,
                         body: {
                           issuer: "https://example.com",
                           authorization_endpoint: "https://example.com/authorize",
                           token_endpoint: "https://example.com/token"
                         }.to_json
                       )

      # Use a fresh storage instance to avoid caching issues
      storage = RubyLLM::MCP::Auth::MemoryStorage.new
      provider = RubyLLM::MCP::Auth::OAuthProvider.new(
        server_url: "https://example.com",
        redirect_uri: "http://localhost:8080/callback",
        storage: storage
      )

      # Access the discoverer and trigger discovery
      discoverer = provider.instance_variable_get(:@discoverer)
      discoverer.discover("https://example.com")
      expect(discovery_stub).to have_been_requested
    end
  end
end
