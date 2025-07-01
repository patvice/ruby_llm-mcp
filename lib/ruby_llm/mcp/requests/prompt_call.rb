# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class PromptCall
        def initialize(coordinator, name:, arguments: {})
          @coordinator = coordinator
          @name = name
          @arguments = arguments
        end

        def call
          @coordinator.request(request_body)
        end

        private

        def request_body
          {
            jsonrpc: "2.0",
            method: "prompts/get",
            params: {
              name: @name,
              arguments: @arguments
            }
          }
        end
      end
    end
  end
end
