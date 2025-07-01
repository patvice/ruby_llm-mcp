# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class ResourceTemplateList
        include Shared::Pagination

        def initialize(coordinator, cursor: nil)
          @coordinator = coordinator
          @cursor = cursor
        end

        def call
          body = merge_pagination(resource_template_list_body)
          @coordinator.request(body)
        end

        private

        def resource_template_list_body
          {
            jsonrpc: "2.0",
            method: "resources/templates/list",
            params: {}
          }
        end
      end
    end
  end
end
