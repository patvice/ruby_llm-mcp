# frozen_string_literal: true

RSpec.describe RubyLLM::MCP do
  it "has a version number" do
    expect(RubyLLM::MCP::VERSION).not_to be_nil
  end

  describe "#client" do
    it "calls RubyLLM::MCP::Client" do
      client = instance_double(RubyLLM::MCP::Client)
      allow(RubyLLM::MCP::Client).to receive(:new).and_return client

      RubyLLM::MCP.client(name: "test", transport_type: "stdio")

      expect(RubyLLM::MCP::Client).to have_received(:new).with(name: "test", transport_type: "stdio")
    end
  end

  describe "#clients" do
    let(:mock_config) do
      [
        { name: "client1", transport_type: "stdio" },
        { name: "client2", transport_type: "sse" }
      ]
    end
    let(:client_stdio) { instance_double(RubyLLM::MCP::Client) }
    let(:client_sse) { instance_double(RubyLLM::MCP::Client) }

    before do
      # Reset clients hash
      RubyLLM::MCP.instance_variable_set(:@clients, nil)
      RubyLLM::MCP.config.mcp_configuration = mock_config

      allow(RubyLLM::MCP::Client).to receive(:new).with(name: "client1",
                                                        transport_type: "stdio").and_return(client_stdio)
      allow(RubyLLM::MCP::Client).to receive(:new).with(name: "client2", transport_type: "sse").and_return(client_sse)
    end

    after do
      MCPTestConfiguration.reset_config!
    end

    it "creates clients from config" do
      clients = RubyLLM::MCP.clients

      expect(clients).to eq({ "client1" => client_stdio, "client2" => client_sse })
    end

    it "caches clients" do
      RubyLLM::MCP.clients
      RubyLLM::MCP.clients

      expect(RubyLLM::MCP::Client).to have_received(:new).with(name: "client1", transport_type: "stdio").once
      expect(RubyLLM::MCP::Client).to have_received(:new).with(name: "client2", transport_type: "sse").once
    end

    it "accepts custom config" do
      custom_config = [{ name: "custom", transport_type: "stdio" }]
      custom_client = instance_double(RubyLLM::MCP::Client)
      allow(RubyLLM::MCP::Client).to receive(:new).with(name: "custom",
                                                        transport_type: "stdio").and_return(custom_client)

      clients = RubyLLM::MCP.clients(custom_config)

      expect(clients.keys).to eq(%w[custom])
      expect(clients["custom"]).to eq(custom_client)
    end

    it "if a client is added, it will also return from the clients hash" do
      custom_client = instance_double(RubyLLM::MCP::Client)
      allow(RubyLLM::MCP::Client).to receive(:new).with(name: "custom",
                                                        transport_type: "stdio").and_return(custom_client)
      RubyLLM::MCP.add_client(name: "custom", transport_type: "stdio")

      clients = RubyLLM::MCP.clients

      expect(clients["custom"]).to eq(custom_client)
    end
  end

  describe "#add_client" do
    let(:client) { instance_double(RubyLLM::MCP::Client) }

    before do
      RubyLLM::MCP.instance_variable_set(:@clients, nil)
      allow(RubyLLM::MCP::Client).to receive(:new).with(name: "test", transport_type: "stdio").and_return(client)
    end

    it "adds a client to the clients hash" do
      RubyLLM::MCP.add_client(name: "test", transport_type: "stdio")

      clients_hash = RubyLLM::MCP.instance_variable_get(:@clients)
      expect(clients_hash["test"]).to eq(client)
    end

    it "doesn't overwrite existing clients" do
      existing_client = instance_double(RubyLLM::MCP::Client)
      RubyLLM::MCP.instance_variable_set(:@clients, { "test" => existing_client })

      RubyLLM::MCP.add_client(name: "test", transport_type: "stdio")

      clients_hash = RubyLLM::MCP.instance_variable_get(:@clients)
      expect(clients_hash["test"]).to eq(existing_client)
      expect(RubyLLM::MCP::Client).not_to have_received(:new)
    end
  end

  describe "#remove_client" do
    let(:client) { instance_double(RubyLLM::MCP::Client) }

    before do
      allow(client).to receive(:stop)
      RubyLLM::MCP.instance_variable_set(:@clients, { "test" => client })
    end

    it "removes client from hash and stops it" do
      result = RubyLLM::MCP.remove_client("test")

      expect(result).to eq(client)
      expect(client).to have_received(:stop)

      clients_hash = RubyLLM::MCP.instance_variable_get(:@clients)
      expect(clients_hash).not_to have_key("test")
    end

    it "returns nil for non-existent client" do
      result = RubyLLM::MCP.remove_client("nonexistent")

      expect(result).to be_nil
    end
  end

  describe "#establish_connection" do
    let(:client_streamable_http) { instance_double(RubyLLM::MCP::Client) }
    let(:client_stdio) { instance_double(RubyLLM::MCP::Client) }
    let(:clients) { { "streamable_http" => client_streamable_http, "stdio" => client_stdio } }

    before do
      allow(RubyLLM::MCP).to receive(:clients).and_return(clients)
      allow(client_streamable_http).to receive(:start)
      allow(client_stdio).to receive(:start)
      allow(client_streamable_http).to receive(:alive?).and_return(true)
      allow(client_stdio).to receive(:alive?).and_return(true)
      allow(client_streamable_http).to receive(:stop)
      allow(client_stdio).to receive(:stop)
    end

    it "starts all clients" do
      RubyLLM::MCP.establish_connection

      expect(client_streamable_http).to have_received(:start)
      expect(client_stdio).to have_received(:start)
    end

    it "returns clients when no block given" do
      result = RubyLLM::MCP.establish_connection

      expect(result).to eq(clients)
    end

    context "when block is given" do
      it "yields clients to the block" do
        yielded_clients = nil
        RubyLLM::MCP.establish_connection do |c|
          yielded_clients = c
        end

        expect(yielded_clients).to eq(clients)
      end

      it "calls close_connection after the block executes" do
        RubyLLM::MCP.establish_connection { |_c| "test" }

        expect(client_streamable_http).to have_received(:stop)
        expect(client_stdio).to have_received(:stop)
      end

      it "calls close_connection even if block raises an exception" do
        expect do
          RubyLLM::MCP.establish_connection { |_c| raise "test error" }
        end.to raise_error("test error")

        expect(client_streamable_http).to have_received(:stop)
        expect(client_stdio).to have_received(:stop)
      end
    end
  end

  describe "#close_connection" do
    let(:alive_client) { instance_double(RubyLLM::MCP::Client) }
    let(:dead_client) { instance_double(RubyLLM::MCP::Client) }
    let(:clients) { { "alive_client" => alive_client, "dead_client" => dead_client } }

    before do
      allow(RubyLLM::MCP).to receive(:clients).and_return(clients)
      allow(alive_client).to receive(:alive?).and_return(true)
      allow(dead_client).to receive(:alive?).and_return(false)
      allow(alive_client).to receive(:stop)
      allow(dead_client).to receive(:stop)
    end

    it "stops all alive clients" do
      RubyLLM::MCP.close_connection

      expect(alive_client).to have_received(:stop)
    end

    it "does not stop clients that are not alive" do
      RubyLLM::MCP.close_connection

      expect(dead_client).not_to have_received(:stop)
    end

    it "checks alive status of all clients" do
      RubyLLM::MCP.close_connection

      expect(alive_client).to have_received(:alive?)
      expect(dead_client).to have_received(:alive?)
    end
  end

  describe "#tools" do
    let(:add) { instance_double(RubyLLM::MCP::Tool, name: "add") }
    let(:sub) { instance_double(RubyLLM::MCP::Tool, name: "sub") }
    let(:multiply) { instance_double(RubyLLM::MCP::Tool, name: "multiply") }
    let(:client_add) { instance_double(RubyLLM::MCP::Client, tools: [add, sub]) }
    let(:client_multiply) { instance_double(RubyLLM::MCP::Client, tools: [multiply]) }

    before do
      RubyLLM::MCP.instance_variable_set(:@clients,
                                         { "client_add" => client_add, "client_multiply" => client_multiply })
    end

    it "returns all tools from all clients" do
      tools = RubyLLM::MCP.tools

      expect(tools).to contain_exactly(add, sub, multiply)
    end

    it "filters out blacklisted tools" do
      tools = RubyLLM::MCP.tools(blacklist: ["add"])

      expect(tools).to contain_exactly(sub, multiply)
    end

    it "only includes whitelisted tools" do
      tools = RubyLLM::MCP.tools(whitelist: %w[add multiply])

      expect(tools).to contain_exactly(add, multiply)
    end

    it "handles duplicate tool names" do
      duplicate_tool = instance_double(RubyLLM::MCP::Tool, name: "add")
      allow(client_multiply).to receive(:tools).and_return([duplicate_tool, multiply])

      tools = RubyLLM::MCP.tools

      expect(tools.size).to eq(3)
      expect(tools.map(&:name)).to contain_exactly("add", "sub", "multiply")
    end
  end

  describe "#configure" do
    it "yields the configuration object" do
      config = instance_double(RubyLLM::MCP::Configuration)
      allow(RubyLLM::MCP).to receive(:config).and_return(config)

      expect { |b| RubyLLM::MCP.configure(&b) }.to yield_with_args(config)
    end
  end

  describe "#config" do
    it "returns a Configuration instance" do
      config = RubyLLM::MCP.config

      expect(config).to be_a(RubyLLM::MCP::Configuration)
    end

    it "memoizes the configuration" do
      config1 = RubyLLM::MCP.config
      config2 = RubyLLM::MCP.config

      expect(config1).to be(config2)
    end
  end

  describe "#configuration" do
    it "is an alias for config" do
      expect(RubyLLM::MCP.method(:configuration)).to eq(RubyLLM::MCP.method(:config))
    end
  end

  describe "#logger" do
    it "returns the logger from config" do
      config = instance_double(RubyLLM::MCP::Configuration)
      logger = instance_double(Logger)
      allow(config).to receive(:logger).and_return(logger)
      allow(RubyLLM::MCP).to receive(:config).and_return(config)

      result = RubyLLM::MCP.logger

      expect(result).to eq(logger)
    end
  end
end
