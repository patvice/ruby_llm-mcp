# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Tool do # rubocop:disable RSpec/SpecFilePathFormat
  let(:tool_payload_class) do
    Struct.new(:name, :description, :input_schema, :output_schema, :meta, keyword_init: true) do
      def [](key)
        return meta if key == "_meta"

        nil
      end
    end
  end

  let(:client_double) { instance_double(RubyLLM::MCP::Client, name: "test-client") }
  let(:adapter_double) { instance_double(RubyLLM::MCP::Adapters::BaseAdapter, client: client_double) }
  let(:sdk_adapter) do
    RubyLLM::MCP::Adapters::MCPSdkAdapter.allocate.tap do |adapter|
      adapter.instance_variable_set(:@config, {})
    end
  end

  it "parses _meta.ui.resourceUri" do
    tool = described_class.new(
      adapter_double,
      {
        "name" => "test_tool",
        "description" => "Tool",
        "inputSchema" => { "type" => "object", "properties" => {} },
        "_meta" => {
          "ui" => {
            "resourceUri" => "ui://tool"
          }
        }
      }
    )

    expect(tool.apps_metadata.resource_uri).to eq("ui://tool")
  end

  it "parses legacy _meta['ui/resourceUri']" do
    tool = described_class.new(
      adapter_double,
      {
        "name" => "test_tool",
        "description" => "Tool",
        "inputSchema" => { "type" => "object", "properties" => {} },
        "_meta" => {
          "ui/resourceUri" => "ui://legacy"
        }
      }
    )

    expect(tool.apps_metadata.resource_uri).to eq("ui://legacy")
  end

  it "defaults visibility to model and app when absent" do
    tool = described_class.new(
      adapter_double,
      {
        "name" => "test_tool",
        "description" => "Tool",
        "inputSchema" => { "type" => "object", "properties" => {} }
      }
    )

    expect(tool.apps_metadata.visibility).to eq(%w[model app])
    expect(tool.apps_metadata.model_visible?).to be(true)
    expect(tool.apps_metadata.app_visible?).to be(true)
  end

  it "provides equivalent apps metadata for native-like and mcp_sdk payloads" do
    native_tool = described_class.new(
      adapter_double,
      {
        "name" => "test_tool",
        "description" => "Tool",
        "inputSchema" => { "type" => "object", "properties" => {} },
        "_meta" => { "ui" => { "resourceUri" => "ui://tool" } }
      }
    )

    sdk_tool_payload = tool_payload_class.new(
      name: "test_tool",
      description: "Tool",
      input_schema: { "type" => "object", "properties" => {} },
      output_schema: {},
      meta: {
        "ui" => { "resourceUri" => "ui://tool" }
      }
    )

    transformed_tool = sdk_adapter.send(:transform_tool, sdk_tool_payload)
    sdk_tool = described_class.new(adapter_double, transformed_tool)

    expect(sdk_tool.apps_metadata.resource_uri).to eq(native_tool.apps_metadata.resource_uri)
  end

  describe RubyLLM::MCP::Resource do
    it "exposes parsed _meta.ui resource metadata" do
      resource = described_class.new(
        adapter_double,
        {
          "name" => "test_resource",
          "uri" => "file://test_resource",
          "description" => "Resource",
          "mimeType" => "text/plain",
          "_meta" => {
            "ui" => {
              "csp" => { "connect-src" => ["https://example.com"] },
              "permissions" => ["read"],
              "domain" => "example.com",
              "prefersBorder" => true
            }
          }
        }
      )

      expect(resource.apps_metadata.csp).to eq({ "connect-src" => ["https://example.com"] })
      expect(resource.apps_metadata.permissions).to eq(["read"])
      expect(resource.apps_metadata.domain).to eq("example.com")
      expect(resource.apps_metadata.prefers_border).to be(true)
    end

    it "provides equivalent apps metadata for native-like and mcp_sdk payloads" do
      native_resource = described_class.new(
        adapter_double,
        {
          "name" => "test_resource",
          "uri" => "file://test_resource",
          "description" => "Resource",
          "mimeType" => "text/plain",
          "_meta" => { "ui" => { "permissions" => ["read"] } }
        }
      )

      transformed_resource = sdk_adapter.send(
        :transform_resource,
        {
          "name" => "test_resource",
          "uri" => "file://test_resource",
          "description" => "Resource",
          "mimeType" => "text/plain",
          "_meta" => { "ui" => { "permissions" => ["read"] } }
        }
      )
      sdk_resource = described_class.new(adapter_double, transformed_resource)

      expect(sdk_resource.apps_metadata.permissions).to eq(native_resource.apps_metadata.permissions)
    end
  end

  describe RubyLLM::MCP::ResourceTemplate do
    it "exposes parsed _meta.ui metadata" do
      template = described_class.new(
        adapter_double,
        {
          "name" => "test_template",
          "uriTemplate" => "file://{name}",
          "description" => "Template",
          "mimeType" => "text/plain",
          "_meta" => {
            "ui" => {
              "permissions" => %w[read write],
              "prefers_border" => false
            }
          }
        }
      )

      expect(template.apps_metadata.permissions).to eq(%w[read write])
      expect(template.apps_metadata.prefers_border).to be(false)
    end

    it "provides equivalent apps metadata for native-like and mcp_sdk payloads" do
      native_template = described_class.new(
        adapter_double,
        {
          "name" => "test_template",
          "uriTemplate" => "file://{name}",
          "description" => "Template",
          "mimeType" => "text/plain",
          "_meta" => { "ui" => { "domain" => "example.com" } }
        }
      )

      transformed_template = sdk_adapter.send(
        :transform_resource_template,
        {
          "name" => "test_template",
          "uriTemplate" => "file://{name}",
          "description" => "Template",
          "mimeType" => "text/plain",
          "_meta" => { "ui" => { "domain" => "example.com" } }
        }
      )
      sdk_template = described_class.new(adapter_double, transformed_template)

      expect(sdk_template.apps_metadata.domain).to eq(native_template.apps_metadata.domain)
    end
  end
end
