# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class LoggingSetLevel
        def initialize(coordinator, level:)
          @coordinator = coordinator
          @level = level
        end

        def call
          @coordinator.request(logging_set_body)
        end

        def logging_set_body
          {
            jsonrpc: "2.0",
            method: "logging/setLevel",
            params: {
              level: @level
            }
          }
        end
      end
    end
  end
end
