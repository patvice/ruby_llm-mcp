# frozen_string_literal: true

module RubyLLM
  module MCP
    module Notifications
      class Cancelled
        def initialize(coordinator, request_id:, reason:)
          @coordinator = coordinator
          @request_id = request_id
          @reason = reason
        end

        def call
          @coordinator.request(cancelled_notification_body, add_id: false, wait_for_response: false)
        end

        private

        def cancelled_notification_body
          {
            jsonrpc: "2.0",
            method: "notifications/cancelled",
            params: {
              requestId: @request_id,
              reason: @reason
            }
          }
        end
      end
    end
  end
end
