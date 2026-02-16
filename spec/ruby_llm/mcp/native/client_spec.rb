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

  def build_client(human_callback: nil)
    described_class.new(
      name: "native-client-spec",
      transport_type: :stdio,
      transport_config: {},
      human_in_the_loop_callback: human_callback
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
end
