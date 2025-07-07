# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Transport do
  let(:coordinator) { instance_double(RubyLLM::MCP::Coordinator) }
  let(:config) { { timeout: 30 } }

  describe ".transports" do
    it "returns a hash of registered transports" do
      transports = described_class.transports

      expect(transports).to be_a(Hash)
      expect(transports).to include(:sse, :stdio, :streamable, :streamable_http)
    end
  end

  describe ".register_transport" do
    let(:custom_transport_class) { Class.new }

    after do
      # Clean up after test
      described_class.transports.delete(:custom)
    end

    it "registers a new transport type" do
      described_class.register_transport(:custom, custom_transport_class)

      expect(described_class.transports[:custom]).to eq(custom_transport_class)
    end
  end

  describe "#initialize" do
    it "sets instance variables" do
      transport = described_class.new(:stdio, coordinator, config: config)

      expect(transport.transport_type).to eq(:stdio)
      expect(transport.coordinator).to eq(coordinator)
      expect(transport.config).to eq(config)
      expect(transport.pid).to eq(Process.pid)
    end
  end

  describe "#transport_protocol" do
    let(:mock_transport) { instance_double(RubyLLM::MCP::Transports::Stdio) }

    before do
      allow(RubyLLM::MCP::Transports::Stdio).to receive(:new).and_return(mock_transport)
    end

    it "builds and returns transport protocol" do
      transport = described_class.new(:stdio, coordinator, config: config)

      protocol = transport.transport_protocol

      expect(protocol).to eq(mock_transport)
      expect(RubyLLM::MCP::Transports::Stdio).to have_received(:new).with(
        coordinator: coordinator,
        **config
      )
    end

    it "memoizes the transport protocol" do
      transport = described_class.new(:stdio, coordinator, config: config)

      protocol1 = transport.transport_protocol
      protocol2 = transport.transport_protocol

      expect(protocol1).to be(protocol2)
      expect(RubyLLM::MCP::Transports::Stdio).to have_received(:new).once
    end

    context "when process ID changes (fork detection)" do
      it "rebuilds transport and restarts coordinator" do
        transport = described_class.new(:stdio, coordinator, config: config)

        # First call
        transport.transport_protocol

        # Simulate process fork
        new_pid = Process.pid + 1
        allow(Process).to receive(:pid).and_return(new_pid)
        allow(coordinator).to receive(:restart_transport)

        # Second call after fork
        transport.transport_protocol

        expect(coordinator).to have_received(:restart_transport)
        expect(transport.pid).to eq(new_pid)
      end
    end
  end

  describe "delegation methods" do
    let(:mock_transport) { instance_double(RubyLLM::MCP::Transports::Stdio) }

    before do
      allow(RubyLLM::MCP::Transports::Stdio).to receive(:new).and_return(mock_transport)
    end

    it "delegates request to transport protocol" do
      transport = described_class.new(:stdio, coordinator, config: config)
      allow(mock_transport).to receive(:request).and_return("response")

      result = transport.request("test")

      expect(result).to eq("response")
      expect(mock_transport).to have_received(:request).with("test")
    end

    it "delegates alive? to transport protocol" do
      transport = described_class.new(:stdio, coordinator, config: config)
      allow(mock_transport).to receive(:alive?).and_return(true)

      result = transport.alive?

      expect(result).to be(true)
      expect(mock_transport).to have_received(:alive?)
    end

    it "delegates close to transport protocol" do
      transport = described_class.new(:stdio, coordinator, config: config)
      allow(mock_transport).to receive(:close)

      transport.close

      expect(mock_transport).to have_received(:close)
    end

    it "delegates start to transport protocol" do
      transport = described_class.new(:stdio, coordinator, config: config)
      allow(mock_transport).to receive(:start)

      transport.start

      expect(mock_transport).to have_received(:start)
    end

    it "delegates set_protocol_version to transport protocol" do
      transport = described_class.new(:stdio, coordinator, config: config)
      allow(mock_transport).to receive(:set_protocol_version)

      transport.set_protocol_version("2.0")

      expect(mock_transport).to have_received(:set_protocol_version).with("2.0")
    end
  end

  describe "#build_transport" do
    context "with valid transport type" do
      it "builds SSE transport" do
        transport = described_class.new(:sse, coordinator, config: config)
        mock_sse = instance_double(RubyLLM::MCP::Transports::SSE)
        allow(RubyLLM::MCP::Transports::SSE).to receive(:new).and_return(mock_sse)

        protocol = transport.send(:build_transport)

        expect(protocol).to eq(mock_sse)
        expect(RubyLLM::MCP::Transports::SSE).to have_received(:new).with(
          coordinator: coordinator,
          **config
        )
      end

      it "builds StreamableHTTP transport for streamable type" do
        transport = described_class.new(:streamable, coordinator, config: config)
        mock_streamable = instance_double(RubyLLM::MCP::Transports::StreamableHTTP)
        allow(RubyLLM::MCP::Transports::StreamableHTTP).to receive(:new).and_return(mock_streamable)

        protocol = transport.send(:build_transport)

        expect(protocol).to eq(mock_streamable)
        expect(RubyLLM::MCP::Transports::StreamableHTTP).to have_received(:new).with(
          coordinator: coordinator,
          **config
        )
      end

      it "builds StreamableHTTP transport for streamable_http type" do
        transport = described_class.new(:streamable_http, coordinator, config: config)
        mock_streamable = instance_double(RubyLLM::MCP::Transports::StreamableHTTP)
        allow(RubyLLM::MCP::Transports::StreamableHTTP).to receive(:new).and_return(mock_streamable)

        protocol = transport.send(:build_transport)

        expect(protocol).to eq(mock_streamable)
        expect(RubyLLM::MCP::Transports::StreamableHTTP).to have_received(:new).with(
          coordinator: coordinator,
          **config
        )
      end
    end

    context "with invalid transport type" do
      it "raises InvalidTransportType error" do
        transport = described_class.new(:invalid, coordinator, config: config)

        expect { transport.send(:build_transport) }.to raise_error(
          RubyLLM::MCP::Errors::InvalidTransportType,
          /Invalid transport type: :invalid/
        )
      end

      it "includes supported transport types in error message" do
        transport = described_class.new(:invalid, coordinator, config: config)

        expect { transport.send(:build_transport) }.to raise_error(
          RubyLLM::MCP::Errors::InvalidTransportType,
          /Supported types are.*sse.*stdio.*streamable/
        )
      end
    end
  end

  describe "registered transport types" do
    it "registers SSE transport" do
      expect(described_class.transports[:sse]).to eq(RubyLLM::MCP::Transports::SSE)
    end

    it "registers Stdio transport" do
      expect(described_class.transports[:stdio]).to eq(RubyLLM::MCP::Transports::Stdio)
    end

    it "registers StreamableHTTP transport for streamable" do
      expect(described_class.transports[:streamable]).to eq(RubyLLM::MCP::Transports::StreamableHTTP)
    end

    it "registers StreamableHTTP transport for streamable_http" do
      expect(described_class.transports[:streamable_http]).to eq(RubyLLM::MCP::Transports::StreamableHTTP)
    end
  end
end
