# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Adapters::RubyLLMAdapter do # rubocop:disable RSpec/SpecFilePathFormat
  let(:extension_id) { RubyLLM::MCP::Extensions::Constants::UI_EXTENSION_ID }
  let(:tool_payload_class) do
    Struct.new(:name, :description, :input_schema, :output_schema, :meta, keyword_init: true) do
      def [](key)
        return meta if key == "_meta"

        nil
      end
    end
  end

  let(:adapter) do
    described_class.allocate.tap do |instance|
      instance.instance_variable_set(
        :@config,
        {
          extensions: {
            extension_id => {
              "ui" => {
                "resourceUri" => "ui://resource"
              }
            }
          }
        }
      )
    end
  end

  it "reports full extension negotiation support" do
    expect(adapter.supports_extension_negotiation?).to be(true)
    expect(adapter.extension_mode).to eq(:full)
  end

  it "suppresses extension capabilities on pre-extension protocol versions" do
    capabilities = adapter.build_client_extensions_capabilities(protocol_version: "2025-03-26")
    expect(capabilities).to eq({})
  end

  it "builds extension capabilities on stable protocol" do
    capabilities = adapter.build_client_extensions_capabilities(protocol_version: "2025-06-18")

    expect(capabilities).to eq(
      extension_id => {
        "ui" => {
          "resourceUri" => "ui://resource"
        }
      }
    )
  end

  it "builds extension capabilities on draft protocol" do
    capabilities = adapter.build_client_extensions_capabilities(
      protocol_version: RubyLLM::MCP::Native::Protocol.draft_version
    )

    expect(capabilities).to eq(
      extension_id => {
        "ui" => {
          "resourceUri" => "ui://resource"
        }
      }
    )
  end

  describe RubyLLM::MCP::Adapters::MCPSdkAdapter do
    let(:adapter) { described_class.allocate }

    before do
      described_class.instance_variable_set(:@extensions_warning_emitted, nil)
      described_class.instance_variable_set(:@extensions_warning_mutex, nil)
    end

    it "reports passive extension support mode" do
      expect(adapter.supports_extension_negotiation?).to be(false)
      expect(adapter.extension_mode).to eq(:passive)
      expect(adapter.build_client_extensions_capabilities(protocol_version: "2026-01-26")).to eq({})
    end

    it "emits passive support warning once per process when extensions are configured" do
      logger = instance_double(Logger, warn: nil)
      allow(RubyLLM::MCP).to receive(:logger).and_return(logger)

      adapter_one = described_class.allocate
      adapter_one.instance_variable_set(:@config, { extensions: { extension_id => {} } })

      adapter_two = described_class.allocate
      adapter_two.instance_variable_set(:@config, { extensions: { extension_id => {} } })

      expect(adapter_one.send(:configured_extensions?)).to be(true)
      expect(adapter_two.send(:configured_extensions?)).to be(true)

      adapter_one.send(:warn_passive_extension_support!)
      adapter_two.send(:warn_passive_extension_support!)

      expect(logger).to have_received(:warn).once
    end

    it "passes through tool _meta for apps metadata parsing parity" do
      tool = tool_payload_class.new(
        name: "test_tool",
        description: "Tool",
        input_schema: {},
        output_schema: {},
        meta: {
          "ui" => { "resourceUri" => "ui://tool" }
        }
      )

      transformed = adapter.send(:transform_tool, tool)

      expect(transformed["_meta"]).to eq(
        "ui" => { "resourceUri" => "ui://tool" }
      )
    end
  end
end
