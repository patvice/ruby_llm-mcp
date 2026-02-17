# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Native::Client do
  let(:extension_id) { RubyLLM::MCP::Extensions::Constants::UI_EXTENSION_ID }
  let(:extensions_capabilities) { { extension_id => {} } }

  describe "extension capability advertisement" do
    it "advertises extensions on stable protocol" do
      client = described_class.new(
        name: "native-stable",
        transport_type: :stdio,
        protocol_version: "2025-06-18",
        extensions_capabilities: extensions_capabilities
      )

      expect(client.client_capabilities[:extensions]).to eq(extensions_capabilities)
    end

    it "does not advertise extensions on pre-extension protocol versions" do
      client = described_class.new(
        name: "native-pre-extension",
        transport_type: :stdio,
        protocol_version: "2025-03-26",
        extensions_capabilities: extensions_capabilities
      )

      expect(client.client_capabilities).not_to have_key(:extensions)
    end

    it "advertises extensions on draft protocol" do
      client = described_class.new(
        name: "native-draft",
        transport_type: :stdio,
        protocol_version: RubyLLM::MCP::Native::Protocol.draft_version,
        extensions_capabilities: extensions_capabilities
      )

      expect(client.client_capabilities[:extensions]).to eq(extensions_capabilities)
    end

    it "advertises extensions for draft labels" do
      client = described_class.new(
        name: "native-draft-label",
        transport_type: :stdio,
        protocol_version: "DRAFT-next",
        extensions_capabilities: extensions_capabilities
      )

      expect(client.client_capabilities[:extensions]).to eq(extensions_capabilities)
    end
  end

  describe "protocol lifecycle" do
    it "resets protocol version to requested version when stopped" do
      client = described_class.new(
        name: "native-lifecycle",
        transport_type: :stdio,
        protocol_version: "2024-11-05"
      )

      transport = instance_double(RubyLLM::MCP::Native::Transport, close: nil)
      client.instance_variable_set(:@transport, transport)
      client.instance_variable_set(:@protocol_version, "2025-06-18")

      client.stop

      expect(client.protocol_version).to eq("2024-11-05")
    end
  end
end
