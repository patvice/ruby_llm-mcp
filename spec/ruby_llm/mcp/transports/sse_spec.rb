# frozen_string_literal: true

class Runner
  class << self
    def instance
      @instance ||= Runner.new
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
      name: "fast-mcp-ruby",
      transport_type: :sse,
      config: {
        url: "http://localhost:#{TestServerManager::PORTS[:sse]}/mcp/sse",
        version: :http1
      }
    )
  end
end

RSpec.describe RubyLLM::MCP::Transports::SSE do
  let(:client) { Runner.instance.client }

  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Runner.instance.start
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Runner.instance.stop
  end

  describe "start" do
    it "starts the transport" do
      expect(client.alive?).to be(true)
    end
  end

  describe "#request" do
    it "can get tool list" do
      tools = client.tools
      expect(tools.count).to eq(2)
    end

    it "can execute a tool" do
      tool = client.tool("CalculateTool")
      result = tool.execute(operation: "add", x: 1.0, y: 2.0)
      expect(result.to_s).to eq("3.0")
    end

    it "can get resource list" do
      resources = client.resources
      expect(resources.count).to eq(1)
    end
  end
end
