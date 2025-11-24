# frozen_string_literal: true

require_relative "../../../lib/ruby_llm/mcp/result"

class FakeLogger
  def error(message)
    @error_message = message
  end

  attr_reader :error_message
end

RSpec.describe RubyLLM::MCP::NotificationHandler do
  let(:client) { instance_double(RubyLLM::MCP::Client) }
  let(:notification_handler) { RubyLLM::MCP::NotificationHandler.new(client) }

  before do
    # Allow client methods that NotificationHandler might call
    allow(client).to receive(:tracking_progress?).and_return(false)
  end

  after do
    MCPTestConfiguration.reset_config!
  end

  describe "notifications/cancelled" do
    it "calls cancel_in_flight_request on the client with the request ID" do
      allow(client).to receive(:cancel_in_flight_request).and_return(true)

      notification = RubyLLM::MCP::Notification.new(
        { "method" => "notifications/cancelled", "params" => { "requestId" => "req-123", "reason" => "Timeout" } }
      )

      notification_handler.execute(notification)

      expect(client).to have_received(:cancel_in_flight_request).with("req-123")
    end

    it "handles cancellation when request is not found" do
      allow(client).to receive(:cancel_in_flight_request).and_return(false)

      notification = RubyLLM::MCP::Notification.new(
        { "method" => "notifications/cancelled", "params" => { "requestId" => "req-456" } }
      )

      expect { notification_handler.execute(notification) }.not_to raise_error
    end

    it "handles cancellation without a reason" do
      allow(client).to receive(:cancel_in_flight_request).and_return(true)

      notification = RubyLLM::MCP::Notification.new(
        { "method" => "notifications/cancelled", "params" => { "requestId" => "req-789" } }
      )

      expect { notification_handler.execute(notification) }.not_to raise_error
      expect(client).to have_received(:cancel_in_flight_request).with("req-789")
    end
  end

  it "calling an unknown notification will log an error and do nothing else" do
    logger = FakeLogger.new
    RubyLLM::MCP.configure do |config|
      config.logger = logger
    end

    notification = RubyLLM::MCP::Notification.new(
      { "method" => "notifications/unknown", "params" => {} }
    )

    notification_handler.execute(notification)
    expect(logger.error_message).to eq("Unknown notification type: notifications/unknown params: {}")
  end
end
