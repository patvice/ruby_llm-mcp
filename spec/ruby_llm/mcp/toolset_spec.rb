# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Toolset do
  let(:read_file) { instance_double(RubyLLM::MCP::Tool, name: "read_file") }
  let(:delete_file) { instance_double(RubyLLM::MCP::Tool, name: "delete_file") }
  let(:list_projects) { instance_double(RubyLLM::MCP::Tool, name: "list_projects") }
  let(:duplicate_read_file) { instance_double(RubyLLM::MCP::Tool, name: "read_file") }
  let(:filesystem_client) do
    instance_double(RubyLLM::MCP::Client, name: "filesystem", tools: [read_file, delete_file])
  end
  let(:projects_client) do
    instance_double(RubyLLM::MCP::Client, name: "projects", tools: [list_projects, duplicate_read_file])
  end
  let(:clients_map) do
    {
      "filesystem" => filesystem_client,
      "projects" => projects_client
    }
  end

  describe "#tools" do
    it "filters to configured client names" do
      toolset = described_class.new(name: :support).from_clients("filesystem")

      tool_names = toolset.tools(clients: clients_map).map(&:name)
      expect(tool_names).to contain_exactly("read_file", "delete_file")
    end

    it "raises when a configured client name is missing" do
      toolset = described_class.new(name: :support).from_clients("missing_client")

      expect do
        toolset.tools(clients: clients_map)
      end.to raise_error(
        RubyLLM::MCP::Errors::ConfigurationError,
        /Unknown MCP client name\(s\): missing_client/
      )
    end

    it "supports include and exclude filters together" do
      toolset = described_class.new(name: :support)
                               .include_tools("read_file", "list_projects")
                               .exclude_tools("list_projects")

      tool_names = toolset.tools(clients: clients_map).map(&:name)
      expect(tool_names).to eq(["read_file"])
    end

    it "deduplicates tools by name across clients" do
      toolset = described_class.new(name: :support)

      tool_names = toolset.tools(clients: clients_map).map(&:name)
      expect(tool_names).to contain_exactly("read_file", "delete_file", "list_projects")
    end
  end
end
