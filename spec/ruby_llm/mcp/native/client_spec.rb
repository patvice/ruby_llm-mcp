# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Native::Client do
  let(:request_result) do
    RubyLLM::MCP::Result.new(
      {
        "result" => {
          "content" => [{ "type" => "text", "text" => "ok" }]
        }
      }
    )
  end

  def build_client(human_callback: nil, **options)
    described_class.new(
      name: "native-client-spec",
      transport_type: :stdio,
      transport_config: {},
      human_in_the_loop_callback: human_callback,
      **options
    )
  end

  describe "#execute_tool" do
    it "fails closed when callback returns non-normalized decision" do
      client = build_client(human_callback: ->(_name, _params) { true })
      allow(client).to receive(:request).and_return(request_result)

      expect(client).not_to receive(:request)
      result = client.execute_tool(name: "add", parameters: { a: 1, b: 2 })

      expect(result.execution_error?).to be true
      expect(result.value.dig("content", 0, "text")).to eq("Tool call was cancelled by the client")
    end

    it "fails closed when decision is denied" do
      decision = RubyLLM::MCP::Handlers::ApprovalDecision.denied(reason: "blocked by policy")
      client = build_client(human_callback: ->(_name, _params) { decision })
      allow(client).to receive(:request).and_return(request_result)

      expect(client).not_to receive(:request)
      result = client.execute_tool(name: "add", parameters: { a: 1, b: 2 })

      expect(result.execution_error?).to be true
    end

    it "executes tool when deferred decision resolves to approved within timeout" do
      promise = RubyLLM::MCP::Handlers::Promise.new
      decision = RubyLLM::MCP::Handlers::ApprovalDecision
                 .deferred(approval_id: "approval-1", timeout: 1)
                 .with_promise(promise)
      client = build_client(human_callback: ->(_name, _params) { decision })
      allow(client).to receive(:request).and_return(request_result)

      Thread.new do
        sleep 0.05
        promise.resolve(true)
      end

      result = client.execute_tool(name: "add", parameters: { a: 1, b: 2 })
      expect(result.execution_error?).to be false
      expect(client).to have_received(:request)
    end

    it "returns cancelled result when deferred decision promise times out" do
      promise = RubyLLM::MCP::Handlers::Promise.new
      decision = RubyLLM::MCP::Handlers::ApprovalDecision
                 .deferred(approval_id: "approval-1", timeout: 0.05)
                 .with_promise(promise)
      client = build_client(human_callback: ->(_name, _params) { decision })
      allow(client).to receive(:request).and_return(request_result)

      result = client.execute_tool(name: "add", parameters: { a: 1, b: 2 })
      expect(result.execution_error?).to be true
      expect(client).not_to have_received(:request)
    end
  end

  describe "#cancel_in_flight_request" do
    it "returns not_found when request is unknown" do
      client = build_client
      expect(client.cancel_in_flight_request("unknown-id")).to eq(:not_found)
    end

    it "returns not_cancellable when operation does not expose cancel" do
      client = build_client
      client.register_in_flight_request("req-1", Object.new)

      expect(client.cancel_in_flight_request("req-1")).to eq(:not_cancellable)
    end

    it "returns operation cancellation outcome and unregisters terminal outcomes" do
      client = build_client
      cancellable = double("Cancellable", cancel: :already_completed)
      client.register_in_flight_request("req-1", cancellable)

      expect(client.cancel_in_flight_request("req-1")).to eq(:already_completed)
      expect(client.cancel_in_flight_request("req-1")).to eq(:not_found)
    end
  end

  describe "#client_capabilities" do
    around do |example|
      original_sampling_enabled = RubyLLM::MCP.config.sampling.enabled
      original_sampling_tools = RubyLLM::MCP.config.sampling.tools
      original_sampling_context = RubyLLM::MCP.config.sampling.context
      original_tasks_enabled = RubyLLM::MCP.config.tasks.enabled
      original_elicitation_form = RubyLLM::MCP.config.elicitation.form
      original_elicitation_url = RubyLLM::MCP.config.elicitation.url

      example.run
    ensure
      RubyLLM::MCP.config.sampling.enabled = original_sampling_enabled
      RubyLLM::MCP.config.sampling.tools = original_sampling_tools
      RubyLLM::MCP.config.sampling.context = original_sampling_context
      RubyLLM::MCP.config.tasks.enabled = original_tasks_enabled
      RubyLLM::MCP.config.elicitation.form = original_elicitation_form
      RubyLLM::MCP.config.elicitation.url = original_elicitation_url
    end

    it "advertises sampling context by default and tools when configured" do
      RubyLLM::MCP.config.sampling.enabled = true
      RubyLLM::MCP.config.sampling.tools = true
      RubyLLM::MCP.config.sampling.context = true

      client = build_client
      capabilities = client.client_capabilities

      expect(capabilities[:sampling]).to eq({ tools: {}, context: {} })
    end

    it "advertises configured elicitation modes when elicitation is enabled" do
      RubyLLM::MCP.config.elicitation.form = true
      RubyLLM::MCP.config.elicitation.url = true

      client = build_client(elicitation_enabled: true)
      capabilities = client.client_capabilities

      expect(capabilities[:elicitation]).to eq({ form: {}, url: {} })
    end

    it "advertises tasks list/cancel support without task-augmented request claims" do
      RubyLLM::MCP.config.tasks.enabled = true

      client = build_client
      capabilities = client.client_capabilities

      expect(capabilities[:tasks]).to eq({ list: {}, cancel: {} })
    end
  end
end
