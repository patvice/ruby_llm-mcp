# frozen_string_literal: true

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

  it "calling cancelled at the moment will do nothing" do
    notification = RubyLLM::MCP::Notification.new(
      { "method" => "notifications/cancelled" }
    )

    expect { notification_handler.execute(notification) }.not_to raise_error
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
