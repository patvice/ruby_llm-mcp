# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Tool do
  let(:client) { instance_double(RubyLLM::MCP::Client, name: "my/client") }
  let(:adapter) { instance_double(RubyLLM::MCP::Adapters::BaseAdapter, client: client) }

  describe "name formatting" do
    it "sanitizes invalid characters in tool names" do
      tool = described_class.new(adapter, { "name" => "search/files", "description" => "Search files" })

      expect(tool.name).to eq("search-files")
    end

    it "sanitizes prefixed names when with_prefix is enabled" do
      tool = described_class.new(
        adapter,
        { "name" => "search/files", "description" => "Search files" },
        with_prefix: true
      )

      expect(tool.name).to eq("my-client_search-files")
    end

    it "executes with the original MCP tool name" do
      result = instance_double(
        RubyLLM::MCP::Result,
        error?: false,
        execution_error?: false,
        value: { "content" => [{ "text" => "ok" }] }
      )
      allow(adapter).to receive(:execute_tool).and_return(result)

      tool = described_class.new(adapter, { "name" => "search/files", "description" => "Search files" })
      tool.execute

      expect(adapter).to have_received(:execute_tool).with(name: "search/files", parameters: {})
    end
  end
end
