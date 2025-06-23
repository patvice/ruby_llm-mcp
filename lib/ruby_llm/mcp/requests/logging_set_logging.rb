# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class LoggingSetLogging
        def initialize(coordinator, level:)
          @coordinator = coordinator
          @level = level
        end

        def call
          coordinator.request(logging_set_logging_body)
        end

        def logging_set_logging_body
          {
            jsonrpc: "2.0",
            method: "logging/setLogging",
            params: {
              level: @level
            }
          }
        end
      end
    end
  end
end
