# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class ToolList
        include Shared::Pagination

        def initialize(coordinator, cursor: nil)
          @coordinator = coordinator
          @cursor = cursor
        end

        def call
          body = merge_pagination(tool_list_body)
          @coordinator.request(body)
        end

        private

        def tool_list_body
          {
            jsonrpc: "2.0",
            method: "tools/list",
            params: {}
          }
        end
      end
    end
  end
end
