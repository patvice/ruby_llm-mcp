# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Native::JsonRpc do
  describe "ErrorCodes" do
    it "defines standard JSON-RPC 2.0 error codes" do
      expect(described_class::ErrorCodes::PARSE_ERROR).to eq(-32_700)
      expect(described_class::ErrorCodes::INVALID_REQUEST).to eq(-32_600)
      expect(described_class::ErrorCodes::METHOD_NOT_FOUND).to eq(-32_601)
      expect(described_class::ErrorCodes::INVALID_PARAMS).to eq(-32_602)
      expect(described_class::ErrorCodes::INTERNAL_ERROR).to eq(-32_603)
      expect(described_class::ErrorCodes::SERVER_ERROR).to eq(-32_000)
    end

    it "defines server error range" do
      expect(described_class::ErrorCodes::SERVER_ERROR_MIN).to eq(-32_099)
      expect(described_class::ErrorCodes::SERVER_ERROR_MAX).to eq(-32_000)
    end
  end

  describe RubyLLM::MCP::Native::JsonRpc::EnvelopeValidator do
    describe "valid requests" do
      it "validates a proper request with id and method" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "method" => "tools/list"
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be true
        expect(validator.request?).to be true
        expect(validator.notification?).to be false
        expect(validator.response?).to be false
      end

      it "validates a request with params" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => { "name" => "test", "arguments" => {} }
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be true
        expect(validator.request?).to be true
      end

      it "validates a request with numeric id" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => 42,
          "method" => "ping"
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be true
      end

      it "validates a request with null id" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => nil,
          "method" => "ping"
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be true
      end
    end

    describe "valid notifications" do
      it "validates a proper notification without id" do
        envelope = {
          "jsonrpc" => "2.0",
          "method" => "notifications/initialized"
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be true
        expect(validator.notification?).to be true
        expect(validator.request?).to be false
        expect(validator.response?).to be false
      end

      it "validates a notification with params" do
        envelope = {
          "jsonrpc" => "2.0",
          "method" => "notifications/cancelled",
          "params" => { "requestId" => "123", "reason" => "timeout" }
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be true
        expect(validator.notification?).to be true
      end
    end

    describe "valid responses" do
      it "validates a successful response with result" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "result" => { "tools" => [] }
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be true
        expect(validator.response?).to be true
        expect(validator.request?).to be false
        expect(validator.notification?).to be false
      end

      it "validates an error response" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "error" => {
            "code" => -32_601,
            "message" => "Method not found"
          }
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be true
        expect(validator.response?).to be true
      end

      it "validates an error response with data" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "error" => {
            "code" => -32_000,
            "message" => "Server error",
            "data" => { "detail" => "Something went wrong" }
          }
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be true
      end
    end

    describe "invalid envelopes" do
      it "rejects envelope without jsonrpc version" do
        envelope = {
          "id" => "123",
          "method" => "ping"
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be false
        expect(validator.error_message).to include("jsonrpc")
      end

      it "rejects envelope with wrong jsonrpc version" do
        envelope = {
          "jsonrpc" => "1.0",
          "id" => "123",
          "method" => "ping"
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be false
        expect(validator.error_message).to include("jsonrpc")
      end

      it "rejects notification with id field" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "method" => "notifications/initialized"
        }
        validator = described_class.new(envelope)

        # This is actually a request, not a notification
        expect(validator.notification?).to be false
        expect(validator.request?).to be true
      end

      it "rejects request without method" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => "123"
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be false
        expect(validator.error_message).to include("must be a request, response, or notification")
      end

      it "rejects request with empty method" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "method" => ""
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be false
        expect(validator.error_message).to include("non-empty 'method'")
      end

      it "rejects response with both result and error" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "result" => {},
          "error" => { "code" => -32_000, "message" => "error" }
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be false
        expect(validator.error_message).to include("either 'result' or 'error', not both")
      end

      it "rejects response with neither result nor error" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => "123"
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be false
      end

      it "rejects response with method field" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "method" => "ping",
          "result" => {}
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be false
        expect(validator.error_message).to include("must not have 'method'")
      end

      it "rejects error response without code" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "error" => {
            "message" => "error"
          }
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be false
        expect(validator.error_message).to include("'code' must be an integer")
      end

      it "rejects error response without message" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "error" => {
            "code" => -32_000
          }
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be false
        expect(validator.error_message).to include("'message' must be a string")
      end

      it "rejects request with invalid params type" do
        envelope = {
          "jsonrpc" => "2.0",
          "id" => "123",
          "method" => "test",
          "params" => "invalid"
        }
        validator = described_class.new(envelope)

        expect(validator.valid?).to be false
        expect(validator.error_message).to include("'params' must be an object or array")
      end

      it "rejects non-hash envelope" do
        validator = described_class.new("not a hash")

        expect(validator.valid?).to be false
        expect(validator.error_message).to include("must be an object")
      end
    end
  end
end
