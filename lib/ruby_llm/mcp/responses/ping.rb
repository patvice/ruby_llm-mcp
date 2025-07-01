# frozen_string_literal: true

module RubyLLM
  module MCP
    module Responses
      class Ping
        def initialize(coordinator, id:)
          @coordinator = coordinator
          @id = id
        end

        def call
          @coordinator.request(ping_response_body, add_id: false, wait_for_response: false)
        end

        private

        def ping_response_body
          {
            jsonrpc: "2.0",
            id: @id,
            result: {}
          }
        end
      end
    end
  end
end
