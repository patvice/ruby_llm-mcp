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
      allow(client).to receive(:cancel_in_flight_request).and_return(:cancelled)

      notification = RubyLLM::MCP::Notification.new(
        { "method" => "notifications/cancelled", "params" => { "requestId" => "req-123", "reason" => "Timeout" } }
      )

      notification_handler.execute(notification)

      expect(client).to have_received(:cancel_in_flight_request).with("req-123")
    end

    it "handles cancellation when request is not found" do
      allow(client).to receive(:cancel_in_flight_request).and_return(:not_found)

      notification = RubyLLM::MCP::Notification.new(
        { "method" => "notifications/cancelled", "params" => { "requestId" => "req-456" } }
      )

      expect { notification_handler.execute(notification) }.not_to raise_error
    end

    it "handles cancellation without a reason" do
      allow(client).to receive(:cancel_in_flight_request).and_return(:cancelled)

      notification = RubyLLM::MCP::Notification.new(
        { "method" => "notifications/cancelled", "params" => { "requestId" => "req-789" } }
      )

      expect { notification_handler.execute(notification) }.not_to raise_error
      expect(client).to have_received(:cancel_in_flight_request).with("req-789")
    end
  end

  describe "notifications/tasks/status" do
    it "forwards task status updates to the adapter when supported" do
      adapter = instance_double(RubyLLM::MCP::Adapters::RubyLLMAdapter)
      allow(client).to receive(:adapter).and_return(adapter)
      allow(adapter).to receive(:task_status_notification)

      notification = RubyLLM::MCP::Notification.new(
        {
          "method" => "notifications/tasks/status",
          "params" => {
            "taskId" => "task-123",
            "status" => "working"
          }
        }
      )

      notification_handler.execute(notification)

      expect(adapter).to have_received(:task_status_notification).with(
        task: hash_including("taskId" => "task-123", "status" => "working")
      )
    end
  end

  describe "notifications/elicitation/complete" do
    it "removes the pending elicitation from registry" do
      allow(RubyLLM::MCP::Handlers::ElicitationRegistry).to receive(:remove)

      notification = RubyLLM::MCP::Notification.new(
        {
          "method" => "notifications/elicitation/complete",
          "params" => {
            "elicitationId" => "elicitation-123"
          }
        }
      )

      notification_handler.execute(notification)

      expect(RubyLLM::MCP::Handlers::ElicitationRegistry).to have_received(:remove).with("elicitation-123")
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
