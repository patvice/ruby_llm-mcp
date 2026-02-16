# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Messages
        # Notification message builders
        # Notifications do not have IDs and do not expect responses
        module Notifications
          extend Helpers

          module_function

          def initialized
            {
              jsonrpc: JSONRPC_VERSION,
              method: METHOD_NOTIFICATION_INITIALIZED
            }
          end

          def cancelled(request_id:, reason:)
            {
              jsonrpc: JSONRPC_VERSION,
              method: METHOD_NOTIFICATION_CANCELLED,
              params: {
                requestId: request_id,
                reason: reason
              }
            }
          end

          def roots_list_changed
            {
              jsonrpc: JSONRPC_VERSION,
              method: METHOD_NOTIFICATION_ROOTS_LIST_CHANGED
            }
          end

          def tasks_status(task:)
            {
              jsonrpc: JSONRPC_VERSION,
              method: METHOD_NOTIFICATION_TASKS_STATUS,
              params: task
            }
          end

          def elicitation_complete(elicitation_id:)
            {
              jsonrpc: JSONRPC_VERSION,
              method: METHOD_NOTIFICATION_ELICITATION_COMPLETE,
              params: {
                elicitationId: elicitation_id
              }
            }
          end
        end
      end
    end
  end
end
