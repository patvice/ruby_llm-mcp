# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class ResourceList < Base
        def call
          client.request(resource_list_body)
        end

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
