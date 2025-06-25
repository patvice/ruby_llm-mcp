# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Progress do
  let(:coordinator) { RubyLLM::MCP::Coordinator.new(client, transport_type: :stdio, handle_progress: nil) }
  let(:client) { RubyLLM::MCP::Client.new(coordinator) }

  describe "#initialize" do
    it "can initialize a progress object" do
      progress = RubyLLM::MCP::Progress.new(coordinator, handle_progress: nil)
    end
  end
end
