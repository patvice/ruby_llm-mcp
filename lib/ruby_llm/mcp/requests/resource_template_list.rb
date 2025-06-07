# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class ResourceTemplateList < Base
        def call
          client.request(resource_template_list_body)
        end

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
