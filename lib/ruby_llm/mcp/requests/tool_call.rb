# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class ToolCall
        include Meta

        def initialize(coordinator, name:, parameters: {})
          @coordinator = coordinator
          @name = name
          @parameters = parameters
        end

        def call
          body = merge_meta(request_body)
          @coordinator.request(body)
        end

        private

        def request_body
          {
            jsonrpc: "2.0",
            method: "tools/call",
            params: {
              name: @name,
              arguments: @parameters
            }
          }
        end
      end
    end
  end
end
