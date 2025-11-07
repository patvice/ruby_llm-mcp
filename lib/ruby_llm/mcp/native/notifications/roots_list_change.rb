# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Notifications
        class RootsListChange
          def initialize(coordinator)
            @coordinator = coordinator
          end

          def call
            @coordinator.request(roots_list_change_notification_body, add_id: false, wait_for_response: false)
          end

          private

          def roots_list_change_notification_body
            {
              jsonrpc: "2.0",
              method: "notifications/roots/list_changed"
            }
          end
        end
      end
    end
  end
end
