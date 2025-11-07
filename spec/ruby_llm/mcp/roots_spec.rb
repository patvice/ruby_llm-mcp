# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Roots do
  let(:adapter) do
    adapter = instance_double("Adapter")
    allow(adapter).to receive(:roots_list_change_notification).and_return(true)
    adapter
  end

  it "can be initialized with an array of paths" do
    roots = RubyLLM::MCP::Roots.new(paths: ["path/to/file1", "path/to/file2"], adapter: adapter)
    expect(roots.paths).to eq(["path/to/file1", "path/to/file2"])
  end

  it "can pass both a string to a path or a pathname object" do
    roots = RubyLLM::MCP::Roots.new(paths: ["path/to/file1", Pathname.new("path/to/file2")], adapter: adapter)
    expect(roots.to_request).to eq([
                                     {
                                       uri: "file://path/to/file1",
                                       name: "file1"
                                     },
                                     {
                                       uri: "file://path/to/file2",
                                       name: "file2"
                                     }
                                   ])
  end

  it "supports Pathname objects" do
    roots = RubyLLM::MCP::Roots.new(paths: [Pathname.new("path/to/file1"), Pathname.new("path/to/file2")],
                                    adapter: adapter)
    expect(roots.to_request).to eq([
                                     {
                                       uri: "file://path/to/file1",
                                       name: "file1"
                                     },
                                     {
                                       uri: "file://path/to/file2",
                                       name: "file2"
                                     }
                                   ])

    roots.add(Pathname.new("path/to/file3"))
    roots.remove(Pathname.new("path/to/file2"))
    roots.remove(Pathname.new("path/to/file1"))
    expect(roots.to_request).to eq([
                                     {
                                       uri: "file://path/to/file3",
                                       name: "file3"
                                     }
                                   ])
  end

  it "calls the list notification change on a remove and an add" do
    roots = RubyLLM::MCP::Roots.new(paths: ["path/to/file1"], adapter: adapter)
    roots.add("path/to/file2")
    expect(adapter).to have_received(:roots_list_change_notification).exactly(1).times

    roots.remove("path/to/file2")
    expect(adapter).to have_received(:roots_list_change_notification).exactly(2).times
  end

  # Integration tests - only run on adapters that support roots
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
  end

  each_client_supporting(:roots) do |config|
    let(:client) { RubyLLM::MCP::Client.new(**config[:options], start: false) }

    after do
      client.stop
      MCPTestConfiguration.reset_config!
    end

    it "client capabilities will include roots" do
      RubyLLM::MCP.config.roots = ["path/to/file1", "path/to/file2"]
      client.start

      capabilities = client.client_capabilities
      expect(capabilities.key?(:roots)).to be(true)
      expect(capabilities[:roots]).to eq({ listChanged: true })
    end

    it "client capabilities will not include roots if not set" do
      client.start

      capabilities = client.client_capabilities
      expect(capabilities.key?(:roots)).to be(false)
    end

    it "client will return error if server requests roots and it's not enabled" do
      client.start
      tool = client.tool("roots-test")
      result = tool.execute
      expect(result.to_s).to include("Roots are not enabled")
    end

    it "client will have roots list from config" do
      paths = ["path/to/file1", "path/to/file2"]
      RubyLLM::MCP.config.roots = paths

      client.start

      tool = client.tool("roots-test")
      result = tool.execute
      paths.each do |path|
        expect(result.to_s).to include("file://#{path}")
      end
    end

    it "client can add roots, and update the roots list" do
      paths = ["path/to/file1"]
      RubyLLM::MCP.config.roots = paths

      client.start
      tool = client.tool("roots-test")
      first_result = tool.execute

      client.roots.add("path/to/file3")
      second_result = tool.execute
      expect(second_result.to_s).to include("file://path/to/file3")
      expect(first_result.to_s).not_to include("file://path/to/file3")
    end

    it "client can remove roots, and update the roots list" do
      paths = ["path/to/file1", "path/to/file2"]
      RubyLLM::MCP.config.roots = paths

      client.start
      tool = client.tool("roots-test")
      first_result = tool.execute

      client.roots.remove("path/to/file2")
      second_result = tool.execute
      expect(first_result.to_s).to include("file://path/to/file2")
      expect(second_result.to_s).not_to include("file://path/to/file2")
    end
  end
end
