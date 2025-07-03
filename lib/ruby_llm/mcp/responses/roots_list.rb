# frozen_string_literal: true

module RubyLLM
  module MCP
    module Responses
      class RootsList
        def initialize(coordinator, roots:, id:)
          @coordinator = coordinator
          @roots = roots
          @id = id
        end

        def call
          @coordinator.request(roots_list_body, add_id: false, wait_for_response: false)
        end

        private

        def roots_list_body
          {
            jsonrpc: "2.0",
            id: @id,
            result: {
              roots: @roots.to_request
            }
          }
        end
      end
    end
  end
end
