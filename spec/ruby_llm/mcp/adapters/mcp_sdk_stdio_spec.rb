# frozen_string_literal: true

class MCPSdkStdioRunner
  class << self
    def instance
      @instance ||= MCPSdkStdioRunner.new
    end
  end

  def start
    client.start
  end

  def stop
    client&.stop
  end

  def client
    @client ||= RubyLLM::MCP::Client.new(
      name: "typescript-mcp-stdio",
      adapter: :mcp_sdk,
      transport_type: :stdio,
      config: {
        command: "bun",
        args: ["spec/fixtures/typescript-mcp/index.ts", "--", "--silent", "--stdio"]
      }
    )
  end
end

RSpec.describe RubyLLM::MCP::Adapters::MCPSdkAdapter do # rubocop:disable RSpec/SpecFilePathFormat
  let(:client) { MCPSdkStdioRunner.instance.client }

  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    if RUBY_VERSION < "3.1.0" || !ClientRunner.mcp_sdk_available?
      skip "Specs require Ruby 3.1+ with the mcp gem available"
    else
      MCPSdkStdioRunner.instance.start
    end
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    if RUBY_VERSION >= "3.1.0" && ClientRunner.mcp_sdk_available?
      MCPSdkStdioRunner.instance.stop
    end
  end

  describe "connection" do
    it "starts the transport and establishes connection" do
      expect(client.alive?).to be(true)
    end
  end

  describe "tools" do
    it "can list tools over stdio" do
      tools = client.tools
      expect(tools.count).to be > 0
    end

    it "can execute a tool over stdio" do
      tool = client.tool("add")
      result = tool.execute(a: 5, b: 3)
      expect(result).not_to be_nil
      expect(result.to_s).to eq("8")
    end
  end

  describe "resources" do
    it "can list resources over stdio" do
      resources = client.resources
      expect(resources.count).to be > 0
    end

    it "can read a resource over stdio" do
      resource = client.resources.first
      content = resource.content
      expect(content).not_to be_nil
      expect(content).to be_a(String)
    end
  end

  describe "prompts" do
    it "can list prompts over stdio" do
      prompts = client.prompts
      expect(prompts.count).to be > 0
      expect(prompts.first).to be_a(RubyLLM::MCP::Prompt)
    end

    it "can execute a prompt over stdio" do
      prompt = client.prompt("say_hello")
      messages = prompt.fetch

      expect(messages).not_to be_empty
      expect(messages.first).to be_a(RubyLLM::Message)
      expect(messages.first.content).to include("Hello")
    end

    it "surfaces prompt argument errors as MCP response errors" do
      prompt = client.prompt("specific_language_greeting")

      expect do
        prompt.fetch({})
      end.to raise_error(RubyLLM::MCP::Errors::ResponseError, /Invalid arguments/)
    end
  end

  describe "resource templates" do
    it "can list resource templates over stdio" do
      templates = client.resource_templates

      expect(templates.count).to be > 0
      expect(templates.first).to be_a(RubyLLM::MCP::ResourceTemplate)
    end
  end

  describe "logging" do
    it "can set log level and receive logging notifications over stdio" do
      received_notification = nil
      client.on_logging(level: RubyLLM::MCP::Logging::DEBUG) do |notification|
        received_notification = notification
      end

      client.tool("log_message").execute(message: "stdio sdk log", level: "debug", logger: "sdk-stdio")

      Timeout.timeout(3) do
        sleep 0.05 until received_notification
      end

      expect(received_notification.params["level"]).to eq("debug")
      expect(received_notification.params["logger"]).to eq("sdk-stdio")
      expect(received_notification.params.dig("data", "message")).to eq("stdio sdk log")
    end
  end

  describe "transport lifecycle" do
    it "can restart the connection" do
      client.stop
      expect(client.alive?).to be(false)

      client.start
      expect(client.alive?).to be(true)

      # Verify functionality after restart
      tools = client.tools
      expect(tools.count).to be > 0
    end
  end
end
