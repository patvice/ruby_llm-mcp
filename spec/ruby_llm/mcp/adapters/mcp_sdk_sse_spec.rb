# frozen_string_literal: true

class MCPSDKSSERunner
  class << self
    def instance
      @instance ||= MCPSDKSSERunner.new
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
      name: "fast-mcp-ruby-sdk",
      adapter: :mcp_sdk,
      transport_type: :sse,
      config: {
        url: "http://localhost:#{TestServerManager::PORTS[:sse]}/mcp/sse",
        version: :http1
      }
    )
  end
end

RSpec.describe RubyLLM::MCP::Adapters::MCPSDKAdapter, "SSE Transport" do
  let(:client) { MCPSDKSSERunner.instance.client }

  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    MCPSDKSSERunner.instance.start
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    MCPSDKSSERunner.instance.stop
  end

  describe "connection" do
    it "starts the transport and establishes connection" do
      expect(client.alive?).to be(true)
    end
  end

  describe "tools" do
    it "can list tools over SSE" do
      tools = client.tools
      expect(tools.count).to eq(2)
    end

    it "can execute a tool over SSE" do
      tool = client.tool("CalculateTool")
      result = tool.execute(operation: "add", x: 1.0, y: 2.0)
      expect(result.to_s).to eq("3.0")
    end
  end

  describe "resources" do
    it "can list resources over SSE" do
      resources = client.resources
      expect(resources.count).to eq(1)
    end

    it "can read a resource over SSE" do
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
      expect(tools.count).to eq(2)
    end
  end
end
