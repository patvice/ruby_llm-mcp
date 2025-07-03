# frozen_string_literal: true

module RubyLLM
  module MCP
    module Notifications
      class Initialize
        def initialize(coordinator)
          @coordinator = coordinator
        end

        def call
          @coordinator.request(notification_body, add_id: false, wait_for_response: false)
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
