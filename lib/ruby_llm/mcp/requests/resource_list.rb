# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class ResourceList
        include Shared::Pagination

        def initialize(coordinator, cursor: nil)
          @coordinator = coordinator
          @cursor = cursor
        end

        def call
          body = merge_pagination(resource_list_body)
          @coordinator.request(body)
        end

        private

        def resource_list_body
          {
            jsonrpc: "2.0",
            method: "resources/list",
            params: {}
          }
        end
      end
    end
  end
end
