# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Transport::Streamable do
  let(:client) do
    RubyLLM::MCP::Client.new(
      name: "test-client",
      transport_type: :streamable,
      request_timeout: 5000,
      config: {
        url: "http://localhost:3005/mcp"
      }
    )
  end

  describe "protocol version negotiation" do
    it "successfully initializes and negotiates protocol version" do
      client.start

      # If protocol version negotiation succeeds, the client should be alive
      expect(client).to be_alive
      expect(client.capabilities).to be_a(RubyLLM::MCP::Capabilities)
    end

    it "can access protocol version through private coordinator for verification" do
      client.start

      # Access coordinator through private instance variable for testing purposes
      coordinator = client.instance_variable_get(:@coordinator)
      expect(coordinator.protocol_version).to be_a(String)
      expect(coordinator.protocol_version).to match(/\d{4}-\d{2}-\d{2}/)
      expect(coordinator.protocol_version).to eq("2025-03-26")
    end
  end

  describe "MCP-Protocol-Version header functionality" do
    it "successfully makes subsequent requests after initialization" do
      client.start

      # These requests should succeed if the protocol version header is correct
      tools = client.tools
      expect(tools).to be_an(Array)
      expect(tools.length).to be > 0

      resources = client.resources
      expect(resources).to be_an(Array)

      prompts = client.prompts
      expect(prompts).to be_an(Array)
    end

    it "can execute tools successfully with proper headers" do
      client.start

      # Tool execution should work if headers are correct
      tool = client.tool("add")
      expect(tool).to be_a(RubyLLM::MCP::Tool)

      result = tool.execute(a: 5, b: 3)
      expect(result).to be_a(RubyLLM::MCP::Content)
      expect(result.to_s).to eq("8")
    end

    it "maintains consistent communication across multiple operations" do
      client.start

      # Multiple operations should all work consistently
      expect(client.tools.length).to be > 0
      expect(client.resources.length).to be > 0
      expect(client.ping).to be(true)

      # Execute a tool to verify full round-trip functionality
      add_tool = client.tool("add")
      result = add_tool.execute(a: 10, b: 20)
      expect(result).to be_a(RubyLLM::MCP::Content)
      expect(result.to_s).to eq("30")
    end
  end

  describe "transport protocol version handling" do
    it "transport can set protocol version after initialization" do
      client.start

      # Verify the transport has the set_protocol_version method
      coordinator = client.instance_variable_get(:@coordinator)
      transport = coordinator.transport
      expect(transport).to respond_to(:set_protocol_version)
    end

    it "protocol version is correctly set on transport" do
      client.start

      # Access transport through coordinator for verification
      coordinator = client.instance_variable_get(:@coordinator)
      transport = coordinator.transport

      # The transport should have a protocol version set
      expect(transport.instance_variable_get(:@protocol_version)).to eq("2025-03-26")
    end
  end

  describe "error handling and compatibility" do
    it "handles normal server communication without issues" do
      client.start

      # Basic functionality should work indicating proper header handling
      expect(client).to be_alive
      expect(client.ping).to be(true)
    end

    it "supports the negotiated protocol version features" do
      client.start

      # Test capabilities that should be available with the protocol version
      expect(client.capabilities.tools_list?).to be(true)
      expect(client.capabilities.resources_list?).to be(true)
    end
  end
end
