# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Result do
  describe "JSON-RPC 2.0 message type detection" do
    describe "#notification?" do
      it "returns true for messages without id but with method" do
        response = {
          "jsonrpc" => "2.0",
          "method" => "notifications/initialized"
        }
        result = described_class.new(response)

        expect(result.notification?).to be true
        expect(result.request?).to be false
        expect(result.response?).to be false
      end

      it "returns true for notifications with params" do
        response = {
          "jsonrpc" => "2.0",
          "method" => "notifications/cancelled",
          "params" => { "requestId" => "123", "reason" => "timeout" }
        }
        result = described_class.new(response)

        expect(result.notification?).to be true
      end

      it "returns false for messages with id" do
        response = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "method" => "ping"
        }
        result = described_class.new(response)

        expect(result.notification?).to be false
      end
    end

    describe "#request?" do
      it "returns true for messages with both id and method" do
        response = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "method" => "ping"
        }
        result = described_class.new(response)

        expect(result.request?).to be true
        expect(result.notification?).to be false
        expect(result.response?).to be false
      end

      it "returns true for requests with params" do
        response = {
          "jsonrpc" => "2.0",
          "id" => "456",
          "method" => "tools/call",
          "params" => { "name" => "test" }
        }
        result = described_class.new(response)

        expect(result.request?).to be true
      end

      it "returns false for notifications (no id)" do
        response = {
          "jsonrpc" => "2.0",
          "method" => "notifications/initialized"
        }
        result = described_class.new(response)

        expect(result.request?).to be false
      end

      it "returns false for responses (no method)" do
        response = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "result" => {}
        }
        result = described_class.new(response)

        expect(result.request?).to be false
      end
    end

    describe "#response?" do
      it "returns true for successful responses with result" do
        response = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "result" => { "tools" => [] }
        }
        result = described_class.new(response)

        expect(result.response?).to be true
        expect(result.request?).to be false
        expect(result.notification?).to be false
      end

      it "returns true for error responses" do
        response = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "error" => {
            "code" => -32_601,
            "message" => "Method not found"
          }
        }
        result = described_class.new(response)

        expect(result.response?).to be true
      end

      it "returns false for requests (has method)" do
        response = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "method" => "ping"
        }
        result = described_class.new(response)

        expect(result.response?).to be false
      end

      it "returns false for notifications (no id)" do
        response = {
          "jsonrpc" => "2.0",
          "method" => "notifications/initialized"
        }
        result = described_class.new(response)

        expect(result.response?).to be false
      end
    end

    describe "specific request types" do
      it "identifies ping requests" do
        response = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "method" => "ping"
        }
        result = described_class.new(response)

        expect(result.ping?).to be true
        expect(result.request?).to be true
      end

      it "identifies roots requests" do
        response = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "method" => "roots/list"
        }
        result = described_class.new(response)

        expect(result.roots?).to be true
        expect(result.request?).to be true
      end

      it "identifies sampling requests" do
        response = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "method" => "sampling/createMessage"
        }
        result = described_class.new(response)

        expect(result.sampling?).to be true
        expect(result.request?).to be true
      end

      it "identifies elicitation requests" do
        response = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "method" => "elicitation/create"
        }
        result = described_class.new(response)

        expect(result.elicitation?).to be true
        expect(result.request?).to be true
      end
    end

    describe "edge cases" do
      it "handles empty result correctly" do
        response = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "result" => {}
        }
        result = described_class.new(response)

        expect(result.response?).to be true
        expect(result.success?).to be true
      end

      it "handles null id in requests" do
        response = {
          "jsonrpc" => "2.0",
          "id" => nil,
          "method" => "ping"
        }
        result = described_class.new(response)

        # null id is still an id in JSON-RPC 2.0
        expect(result.request?).to be false # because id is nil
        expect(result.notification?).to be true # no id means notification
      end
    end
  end
end
