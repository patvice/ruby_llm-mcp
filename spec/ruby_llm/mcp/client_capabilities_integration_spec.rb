# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Client Capabilities Integration" do # rubocop:disable RSpec/DescribeClass
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
  end

  before do
    MCPTestConfiguration.reset_config!
    MCPTestConfiguration.configure_ruby_llm!
  end

  after do
    next unless respond_to?(:client)

    client.stop if client.alive?
  end

  def parse_capabilities_from_tool_response(content)
    json = content.to_s.sub(/\AClient capabilities:\s*/, "")
    JSON.parse(json)
  end

  each_client_supporting(:tasks) do |config|
    let(:client) { RubyLLM::MCP::Client.new(**config[:options], start: false) }

    it "advertises tasks list/cancel without task-augmented request claims" do
      RubyLLM::MCP.configure do |config|
        config.tasks.enabled = true
      end

      client.start
      tool = wait_for_tool(client, "client-capabilities")
      capabilities = parse_capabilities_from_tool_response(tool.execute)

      expect(capabilities.dig("tasks", "list")).to eq({})
      expect(capabilities.dig("tasks", "cancel")).to eq({})
      expect(capabilities.dig("tasks", "requests")).to be_nil
    end
  end

  each_client_supporting(:sampling) do |config|
    let(:client) { RubyLLM::MCP::Client.new(**config[:options], start: false) }

    it "advertises sampling context/tools capability flags from configuration" do
      RubyLLM::MCP.configure do |config|
        config.sampling.enabled = true
        config.sampling.context = true
        config.sampling.tools = true
      end

      client.start
      tool = wait_for_tool(client, "client-capabilities")
      capabilities = parse_capabilities_from_tool_response(tool.execute)

      expect(capabilities.dig("sampling", "context")).to eq({})
      expect(capabilities.dig("sampling", "tools")).to eq({})
    end
  end

  each_client_supporting(:elicitation) do |config|
    let(:client) { RubyLLM::MCP::Client.new(**config[:options], start: false) }

    it "advertises elicitation form/url when handler is configured before start" do
      RubyLLM::MCP.configure do |config|
        config.elicitation.form = true
        config.elicitation.url = true
      end

      client.on_elicitation do |elicitation|
        elicitation.structured_response = { "confirmed" => true }
        true
      end

      client.start
      tool = wait_for_tool(client, "client-capabilities")
      capabilities = parse_capabilities_from_tool_response(tool.execute)

      expect(capabilities.dig("elicitation", "form")).to eq({})
      expect(capabilities.dig("elicitation", "url")).to eq({})
    end
  end
end
