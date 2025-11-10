# frozen_string_literal: true

class MCPSDKStreamableRunner
  class << self
    def instance
      @instance ||= MCPSDKStreamableRunner.new
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
      name: "typescript-mcp-streamable",
      adapter: :mcp_sdk,
      transport_type: :streamable_http,
      config: {
        url: "http://localhost:#{TestServerManager::PORTS[:http]}/mcp"
      }
    )
  end
end

RSpec.describe RubyLLM::MCP::Adapters::MCPSDKAdapter do # rubocop:disable RSpec/SpecFilePathFormat
  let(:client) { MCPSDKStreamableRunner.instance.client }

  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    MCPSDKStreamableRunner.instance.start
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    MCPSDKStreamableRunner.instance.stop
  end

  describe "connection" do
    it "starts the transport and establishes connection" do
      expect(client.alive?).to be(true)
    end
  end

  describe "tools" do
    it "can list tools over streamable HTTP" do
      tools = client.tools
      expect(tools.count).to be > 0
    end

    it "can execute a tool over streamable HTTP" do
      tool = client.tool("add")
      result = tool.execute(a: 5, b: 3)
      expect(result).not_to be_nil
      expect(result.to_s).to eq("8")
    end
  end

  describe "resources" do
    it "can list resources over streamable HTTP" do
      resources = client.resources
      expect(resources.count).to be > 0
    end

    it "can read a resource over streamable HTTP" do
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
