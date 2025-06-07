# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Client do
  let(:name) { "name" }
  let(:transport_type) { "stdio" }

  let(:initialization) do
    instance_double(RubyLLM::MCP::Requests::Initialization)
  end

  let(:notification) do
    instance_double(RubyLLM::MCP::Requests::Notification)
  end

  let(:stdio_transport) do
    instance_double(RubyLLM::MCP::Transport::Stdio)
  end

  let(:sse_transport) do
    instance_double(RubyLLM::MCP::Transport::SSE)
  end

  let(:streamable_transport) do
    instance_double(RubyLLM::MCP::Transport::Streamable)
  end

  before do
    allow(RubyLLM::MCP::Requests::Initialization).to receive(:new).and_return initialization
    allow(initialization).to receive(:call).and_return({ "result" => { "capabilities" => [] } })

    allow(RubyLLM::MCP::Requests::Notification).to receive(:new).and_return notification
    allow(notification).to receive(:call)

    allow(RubyLLM::MCP::Transport::Stdio).to receive(:new).and_return stdio_transport
    allow(RubyLLM::MCP::Transport::SSE).to receive(:new).and_return sse_transport
    allow(RubyLLM::MCP::Transport::Streamable).to receive(:new).and_return streamable_transport
  end

  describe "#initialize" do
    subject(:client) do
      described_class.new(name: name, transport_type: transport_type)
    end

    it "sets the name" do
      expect(client.name).to eq name
    end

    it "defaults to a request time of 8 seconds" do
      expect(client.request_timeout).to eq 8000
    end

    it "defaults to a nil reverse proxy url" do
      expect(client.reverse_proxy_url).to be_nil
    end

    it "defaults to an empty config" do
      expect(client.config).to be_empty
    end

    context "with a transport type of stdio" do
      subject(:client) do
        described_class.new(name: name, transport_type: transport_type, config: config)
      end

      let(:config) do
        {
          command: "command",
          args: "args",
          env: { "NAME" => "VALUE" }
        }
      end

      it "creates a Stdio transport" do
        expect(client.transport).to eq stdio_transport
      end

      it "initializes the transport with the command, args, and env" do
        client

        expect(RubyLLM::MCP::Transport::Stdio)
          .to have_received(:new)
          .with("command", { args: "args", env: { "NAME" => "VALUE" } })
      end
    end

    context "with a transport type of sse" do
      subject(:client) do
        described_class.new(name: name, transport_type: transport_type, config: config)
      end

      let(:transport_type) { "sse" }
      let(:config) { { url: "https://url.com", headers: { "Authorization" => "Bearer token" } } }

      it "creates a SSE transport" do
        expect(client.transport).to eq sse_transport
      end

      it "initializes the transport with the url" do
        client

        expect(RubyLLM::MCP::Transport::SSE)
          .to have_received(:new)
          .with("https://url.com", headers: { "Authorization" => "Bearer token" })
      end
    end

    context "with a transport type of streamable" do
      subject(:client) do
        described_class.new(name: name, transport_type: transport_type, config: config)
      end

      let(:transport_type) { "streamable" }
      let(:config) { { url: "https://url.com", headers: { "Authorization" => "Bearer token" } } }

      it "creates a Streamable transport" do
        expect(client.transport).to eq streamable_transport
      end

      it "initializes the transport with the url and headers" do
        client

        expect(RubyLLM::MCP::Transport::Streamable)
          .to have_received(:new)
          .with("https://url.com", headers: { "Authorization" => "Bearer token" })
      end
    end

    context "with an unknown transport type" do
      let(:transport_type) { "unknown" }

      it "raises an error" do
        expect { client }.to raise_error(/Invalid transport type/)
      end
    end
  end

  describe "#request" do
    subject(:request) do
      described_class.new(name: name, transport_type: transport_type).request("body")
    end

    before do
      allow(stdio_transport).to receive(:request).and_return "result"
    end

    it "calls transport#request and returns the result" do
      expect(request).to eq "result"

      expect(stdio_transport).to have_received(:request).with("body")
    end

    it "waits for the response by default" do
      request

      expect(stdio_transport).to have_received(:request).with(anything)
    end

    context "with wait_for_response: false" do
      subject(:request) do
        described_class.new(name: name, transport_type: transport_type).request("body", add_id: true,
                                                                                        wait_for_response: false)
      end

      it "does not wait for the response" do
        request

        expect(stdio_transport).to have_received(:request).with(anything, add_id: true, wait_for_response: false)
      end
    end
  end

  describe "#tools" do
    subject(:tools) do
      client.tools
    end

    let(:client) do
      described_class.new(name: name, transport_type: transport_type)
    end

    let(:tool_list) { instance_double(RubyLLM::MCP::Requests::ToolList) }
    let(:tools_response) { { "result" => { "tools" => %w[tool1 tool2] } } }
    let(:mcp_tools) do
      [
        instance_double(RubyLLM::MCP::Tool),
        instance_double(RubyLLM::MCP::Tool)
      ]
    end

    before do
      allow(RubyLLM::MCP::Requests::ToolList).to receive(:new).and_return tool_list
      allow(tool_list).to receive(:call).and_return tools_response

      allow(RubyLLM::MCP::Tool).to receive(:new).and_return(*mcp_tools)
    end

    it "makes a tool list request" do
      expect(tools).to eq mcp_tools

      expect(RubyLLM::MCP::Requests::ToolList).to have_received(:new).with(client)
      expect(tool_list).to have_received(:call)
    end

    it "wraps the returned tools" do
      expect(tools).to eq mcp_tools

      expect(RubyLLM::MCP::Tool).to have_received(:new).with(client, "tool1")
      expect(RubyLLM::MCP::Tool).to have_received(:new).with(client, "tool2")
    end

    it "caches by default" do
      client.tools
      client.tools

      expect(tool_list).to have_received(:call).once
    end

    context "with refresh: true" do
      it "ignores the cache" do
        client.tools(refresh: true)
        client.tools(refresh: true)

        expect(tool_list).to have_received(:call).twice
      end
    end
  end

  describe "#execute_tool" do
    subject(:execute_tool) do
      client.execute_tool(name: "name", parameters: "parameters")
    end

    let(:client) do
      described_class.new(name: name, transport_type: transport_type)
    end

    let(:tool_call) do
      instance_double(RubyLLM::MCP::Requests::ToolCall)
    end

    let(:response) do
      {
        "result" => {
          "content" => [
            { "text" => "line 1" },
            { "text" => "line 2" }
          ]
        }
      }
    end

    before do
      allow(RubyLLM::MCP::Requests::ToolCall).to receive(:new).and_return tool_call
      allow(tool_call).to receive(:call).and_return response
    end

    it "makes a tool call request" do
      execute_tool

      expect(RubyLLM::MCP::Requests::ToolCall).to have_received(:new)
        .with(client, name: "name", parameters: "parameters")
    end

    it "concatenates the results" do
      expect(execute_tool).to eq "line 1\nline 2"
    end
  end
end
