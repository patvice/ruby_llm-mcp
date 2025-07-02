# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Roots do
  it "can be initialized with an array of paths" do
    roots = RubyLLM::MCP::Roots.new(paths: ["path/to/file1", "path/to/file2"])
    expect(roots.paths).to eq(["path/to/file1", "path/to/file2"])
  end

  it "can pass both a string to a path or a pathname object" do
    roots = RubyLLM::MCP::Roots.new(paths: ["path/to/file1", Pathname.new("path/to/file2")])
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

  CLIENT_OPTIONS.each do |config|
    context "with #{config[:name]}" do
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

      it "client can add roots, and update the roost list" do
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

      it "client can remove roots, and update the roost list" do
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
end
