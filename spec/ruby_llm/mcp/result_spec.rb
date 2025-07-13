# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Result do
  describe "#initialize" do
    it "initializes with response data" do
      response = {
        "id" => "123",
        "method" => "ping",
        "result" => { "data" => "test" },
        "params" => { "param1" => "value1" }
      }

      result = described_class.new(response, session_id: "session123")

      expect(result.id).to eq("123")
      expect(result.result).to eq({ "data" => "test" })
      expect(result.params).to eq({ "param1" => "value1" })
      expect(result.session_id).to eq("session123")
      expect(result.response).to eq(response)
    end

    it "initializes with error data" do
      response = {
        "id" => "123",
        "method" => "ping",
        "error" => { "code" => -1, "message" => "error" }
      }

      result = described_class.new(response)

      expect(result.error).to eq({ "code" => -1, "message" => "error" })
      expect(result.response).to eq(response)
    end

    it "handles missing optional fields" do
      response = { "id" => "123" }

      result = described_class.new(response)

      expect(result.result).to eq({})
      expect(result.params).to eq({})
      expect(result.error).to eq({})
      expect(result.session_id).to be_nil
    end

    it "extracts next_cursor from nested result" do
      response = {
        "result" => {
          "nextCursor" => "cursor123",
          "data" => "test"
        }
      }

      result = described_class.new(response)

      expect(result.next_cursor).to eq("cursor123")
    end

    it "handles isError flag in result" do
      response = {
        "result" => {
          "isError" => true,
          "data" => "test"
        }
      }

      result = described_class.new(response)

      expect(result.execution_error?).to be(true)
    end
  end

  describe "Request method predicate methods" do
    it "identifies ping requests" do
      response = { "method" => "ping" }
      result = described_class.new(response)

      expect(result.ping?).to be(true)
      expect(result.roots?).to be(false)
      expect(result.sampling?).to be(false)
    end

    it "identifies roots requests" do
      response = { "method" => "roots/list" }
      result = described_class.new(response)

      expect(result.roots?).to be(true)
      expect(result.ping?).to be(false)
      expect(result.sampling?).to be(false)
    end

    it "identifies sampling requests" do
      response = { "method" => "sampling/createMessage" }
      result = described_class.new(response)

      expect(result.sampling?).to be(true)
      expect(result.ping?).to be(false)
      expect(result.roots?).to be(false)
    end
  end

  describe "#value" do
    it "is an alias for result" do
      response = { "result" => { "data" => "test" } }
      result = described_class.new(response)

      expect(result.value).to eq(result.result)
    end
  end

  describe "#notification" do
    it "returns a Notification object" do
      response = { "method" => "notifications/test", "params" => { "data" => "test" } }
      result = described_class.new(response)

      notification = result.notification

      expect(notification).to be_a(RubyLLM::MCP::Notification)
      expect(notification.type).to eq("notifications/test")
      expect(notification.params).to eq({ "data" => "test" })
    end
  end

  describe "#to_error" do
    it "returns an Error object" do
      response = { "error" => { "code" => -1, "message" => "test error" } }
      result = described_class.new(response)

      error = result.to_error

      expect(error).to be_a(RubyLLM::MCP::Error)
    end
  end

  describe "#execution_error?" do
    it "returns true when result has isError flag" do
      response = { "result" => { "isError" => true } }
      result = described_class.new(response)

      expect(result.execution_error?).to be(true)
    end

    it "returns false when result has no isError flag" do
      response = { "result" => { "data" => "test" } }
      result = described_class.new(response)

      expect(result.execution_error?).to be(false)
    end
  end

  describe "#raise_error!" do
    it "raises ResponseError with error details" do
      response = { "error" => { "code" => -1, "message" => "test error" } }
      result = described_class.new(response)

      expect { result.raise_error! }.to raise_error(RubyLLM::MCP::Errors::ResponseError)
    end
  end

  describe "#matching_id?" do
    it "returns true for matching string IDs" do
      response = { "id" => "123" }
      result = described_class.new(response)

      expect(result.matching_id?("123")).to be(true)
    end

    it "returns true for matching numeric IDs" do
      response = { "id" => 123 }
      result = described_class.new(response)

      expect(result.matching_id?(123)).to be(true)
    end

    it "returns false for non-matching IDs" do
      response = { "id" => "123" }
      result = described_class.new(response)

      expect(result.matching_id?("456")).to be(false)
    end

    it "returns false when id is nil" do
      response = {}
      result = described_class.new(response)

      expect(result.matching_id?("123")).to be(false)
    end
  end

  describe "#notification?" do
    it "returns true for notification methods" do
      response = { "method" => "notifications/test" }
      result = described_class.new(response)

      expect(result.notification?).to be(true)
    end

    it "returns false for non-notification methods" do
      response = { "method" => "ping" }
      result = described_class.new(response)

      expect(result.notification?).to be(false)
    end

    it "returns false when method is nil" do
      response = {}
      result = described_class.new(response)

      expect(result.notification?).to be(false)
    end
  end

  describe "#next_cursor?" do
    it "returns true when next_cursor exists" do
      response = { "result" => { "nextCursor" => "cursor123" } }
      result = described_class.new(response)

      expect(result.next_cursor?).to be(true)
    end

    it "returns false when next_cursor is nil" do
      response = { "result" => {} }
      result = described_class.new(response)

      expect(result.next_cursor?).to be(false)
    end
  end

  describe "#request?" do
    it "returns true for requests with method but no result/error" do
      response = { "method" => "ping" }
      result = described_class.new(response)

      expect(result.request?).to be(true)
    end

    it "returns false for notifications" do
      response = { "method" => "notifications/test" }
      result = described_class.new(response)

      expect(result.request?).to be(false)
    end

    it "returns false when method is nil" do
      response = {}
      result = described_class.new(response)

      expect(result.request?).to be(false)
    end

    it "returns false when result is present" do
      response = { "method" => "ping", "result" => { "data" => "test" } }
      result = described_class.new(response)

      expect(result.request?).to be(false)
    end

    it "returns false when error is present" do
      response = { "method" => "ping", "error" => { "code" => -1 } }
      result = described_class.new(response)

      expect(result.request?).to be(false)
    end
  end

  describe "#response?" do
    it "returns true for responses with id and result" do
      response = { "id" => "123", "result" => { "data" => "test" } }
      result = described_class.new(response)

      expect(result.response?).to be(true)
    end

    it "returns true for responses with id and error" do
      response = { "id" => "123", "error" => { "code" => -1 } }
      result = described_class.new(response)

      expect(result.response?).to be(true)
    end

    it "returns false when id is missing" do
      response = { "result" => { "data" => "test" } }
      result = described_class.new(response)

      expect(result.response?).to be(false)
    end

    it "returns false when method is present" do
      response = { "id" => "123", "method" => "ping", "result" => { "data" => "test" } }
      result = described_class.new(response)

      expect(result.response?).to be(false)
    end
  end

  describe "#success?" do
    it "returns true when result is not empty" do
      response = { "result" => { "data" => "test" } }
      result = described_class.new(response)

      expect(result.success?).to be(true)
    end

    it "returns false when result is empty" do
      response = { "result" => {} }
      result = described_class.new(response)

      expect(result.success?).to be(false)
    end
  end

  describe "#tool_success?" do
    it "returns true when success and no execution error" do
      response = { "result" => { "data" => "test" } }
      result = described_class.new(response)

      expect(result.tool_success?).to be(true)
    end

    it "returns false when success but has execution error" do
      response = { "result" => { "data" => "test", "isError" => true } }
      result = described_class.new(response)

      expect(result.tool_success?).to be(false)
    end

    it "returns false when not success" do
      response = { "result" => {} }
      result = described_class.new(response)

      expect(result.tool_success?).to be(false)
    end
  end

  describe "#error?" do
    it "returns true when error is not empty" do
      response = { "error" => { "code" => -1, "message" => "error" } }
      result = described_class.new(response)

      expect(result.error?).to be(true)
    end

    it "returns false when error is empty" do
      response = { "error" => {} }
      result = described_class.new(response)

      expect(result.error?).to be(false)
    end
  end

  describe "#to_s and #inspect" do
    it "provides detailed string representation" do
      response = {
        "id" => "123",
        "method" => "ping",
        "result" => { "data" => "test" },
        "error" => { "code" => -1 },
        "params" => { "param1" => "value1" }
      }
      result = described_class.new(response)

      inspect_string = result.inspect

      expect(inspect_string).to include("id: 123")
      expect(inspect_string).to include("method: ping")
    end

    it "to_s is an alias for inspect" do
      response = { "id" => "123" }
      result = described_class.new(response)

      expect(result.to_s).to eq(result.inspect)
    end
  end

  describe RubyLLM::MCP::Notification do
    describe "#initialize" do
      it "extracts type and params from response" do
        response = {
          "method" => "notifications/test",
          "params" => { "data" => "test" }
        }

        notification = described_class.new(response)

        expect(notification.type).to eq("notifications/test")
        expect(notification.params).to eq({ "data" => "test" })
      end
    end
  end
end
