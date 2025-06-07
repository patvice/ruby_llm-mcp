# frozen_string_literal: true

class RubyLLM::MCP::Requests::Notification < RubyLLM::MCP::Requests::Base
  def call
    client.request(notification_body, add_id: false, wait_for_response: false)
  end

  def notification_body
    {
      jsonrpc: "2.0",
      method: "notifications/initialized"
    }
  end
end
