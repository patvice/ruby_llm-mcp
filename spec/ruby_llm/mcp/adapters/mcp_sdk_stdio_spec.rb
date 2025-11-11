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
    if RUBY_VERSION < "3.2.0"
      skip "Specs require Ruby 3.2+"
    else
      MCPSdkStdioRunner.instance.start
    end
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    MCPSdkStdioRunner.instance.stop
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
