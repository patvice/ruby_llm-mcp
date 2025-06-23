# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class InitializeNotification < RubyLLM::MCP::Requests::Base
        def call
          coordinator.request(notification_body, add_id: false, wait_for_response: false)
        end

        def notification_body
          {
            jsonrpc: "2.0",
            method: "notifications/initialized"
          }
        end
      end
    end
  end
end
