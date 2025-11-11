# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Responses
        class Elicitation
          def initialize(coordinator, id:, elicitation:)
            @coordinator = coordinator
            @id = id
            @action = elicitation[:action]
            @content = elicitation[:content]
          end

          def call
            @coordinator.request(elicitation_response_body, add_id: false, wait_for_response: false)
          end

          private

          def elicitation_response_body
            {
              jsonrpc: "2.0",
              id: @id,
              result: {
                action: @action,
                content: @content
              }.compact
            }
          end
        end
      end
    end
  end
end
