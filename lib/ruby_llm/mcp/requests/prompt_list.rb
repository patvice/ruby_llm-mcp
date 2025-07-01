# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class PromptList < Base
        def call
          coordinator.request(request_body)
        end

        private

        def request_body
          {
            jsonrpc: "2.0",
            method: "prompts/list",
            params: {}
          }
        end
      end
    end
  end
end
