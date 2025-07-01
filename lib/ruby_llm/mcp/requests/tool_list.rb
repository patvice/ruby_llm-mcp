# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class ToolList < RubyLLM::MCP::Requests::Base
        def call
          coordinator.request(tool_list_body)
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
