# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class PingResponse < Base
        def call
          client.request(ping_request)
        end

        def ping_response
          {
            jsonrpc: "2.0",
            result: {}
          }
        end
      end
    end
  end
end
