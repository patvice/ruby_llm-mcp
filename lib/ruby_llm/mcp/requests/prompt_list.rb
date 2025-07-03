# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class PromptList
        include Shared::Pagination

        def initialize(coordinator, cursor: nil)
          @coordinator = coordinator
          @cursor = cursor
        end

        def call
          body = merge_pagination(request_body)
          @coordinator.request(body)
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
