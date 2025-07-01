# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class Ping
        def initialize(coordinator)
          @coordinator = coordinator
        end

        def call
          @coordinator.request(ping_body)
        end

        def ping_body
          {
            jsonrpc: "2.0",
            method: "ping"
          }
        end
      end
    end
  end
end
