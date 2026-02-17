# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Client do
  after do
    RubyLLM::MCP.config.reset!
    MCPTestConfiguration.configure!
  end

  describe "protocol version resolution" do
    let(:ruby_llm_adapter) do
      instance_double(
        RubyLLM::MCP::Adapters::RubyLLMAdapter,
        supports?: false,
        alive?: false
      )
    end

    let(:mcp_sdk_adapter) do
      instance_double(
        RubyLLM::MCP::Adapters::MCPSdkAdapter,
        supports?: false,
        alive?: false
      )
    end

    before do
      allow(RubyLLM::MCP::Adapters::RubyLLMAdapter).to receive(:new).and_return(ruby_llm_adapter)
      allow(RubyLLM::MCP::Adapters::MCPSdkAdapter).to receive(:new).and_return(mcp_sdk_adapter)
    end

    it "prioritizes per-client protocol_version for ruby_llm adapter" do
      RubyLLM::MCP.configure do |config|
        config.protocol_version = "2025-03-26"
      end

      build_client(
        adapter: :ruby_llm,
        name: "protocol-client-ruby-llm",
        config: { protocol_version: "2024-11-05" }
      )

      expect(RubyLLM::MCP::Adapters::RubyLLMAdapter).to have_received(:new).with(
        instance_of(described_class),
        transport_type: :stdio,
        config: hash_including(protocol_version: "2024-11-05")
      )
    end

    it "prioritizes per-client protocol_version for mcp_sdk adapter" do
      RubyLLM::MCP.configure do |config|
        config.protocol_version = "2025-03-26"
      end

      build_client(
        adapter: :mcp_sdk,
        name: "protocol-client-mcp-sdk",
        config: { protocol_version: "2024-11-05" }
      )

      expect(RubyLLM::MCP::Adapters::MCPSdkAdapter).to have_received(:new).with(
        instance_of(described_class),
        transport_type: :stdio,
        config: hash_including(protocol_version: "2024-11-05")
      )
    end

    it "uses global draft protocol when protocol_track is draft and no explicit override is set" do
      RubyLLM::MCP.configure do |config|
        config.protocol_track = :draft
        config.protocol_version = nil
      end

      build_client(
        adapter: :ruby_llm,
        name: "protocol-client-draft"
      )

      expect(RubyLLM::MCP::Adapters::RubyLLMAdapter).to have_received(:new).with(
        instance_of(described_class),
        transport_type: :stdio,
        config: hash_including(protocol_version: RubyLLM::MCP::Native::Protocol.draft_version)
      )
    end

    it "merges global and per-client extension config with canonicalized ids" do
      RubyLLM::MCP.configure do |config|
        config.extensions.enable_apps
      end

      build_client(
        adapter: :ruby_llm,
        name: "extension-merge-client",
        config: {
          extensions: {
            RubyLLM::MCP::Extensions::Constants::APPS_EXTENSION_ALIAS => {
              mimeTypes: ["text/html;profile=mcp-app", "text/html"]
            }
          }
        }
      )

      expect(RubyLLM::MCP::Adapters::RubyLLMAdapter).to have_received(:new).with(
        instance_of(described_class),
        transport_type: :stdio,
        config: hash_including(extensions: expected_extensions)
      )
    end

    def expected_extensions
      {
        RubyLLM::MCP::Extensions::Constants::UI_EXTENSION_ID => {
          "mimeTypes" => ["text/html;profile=mcp-app", "text/html"]
        }
      }
    end

    def build_client(adapter:, name:, config: {})
      described_class.new(
        name: name,
        adapter: adapter,
        transport_type: :stdio,
        start: false,
        config: {
          command: "echo",
          args: ["ok"]
        }.merge(config)
      )
    end
  end
end
