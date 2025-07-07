# frozen_string_literal: true

module RubyLLM
  module MCP
    module Responses
      class Elicitation
        def initialize(coordinator, id:, action:, content:)
          @coordinator = coordinator
          @id = id
          @action = action
          @content = content
        end

        def call
          @coordinator.request(elicitation_response_body, add_id: false, wait_for_response: false)
        end

        private

        def elicitation_response_body
          {
            jsonrpc: "2.0",
            id: @id,
            result: "elicitation/create",
            params: {
              action: @action,
              content: @content
            }.compact
          }
        end
      end
    end
  end
end
