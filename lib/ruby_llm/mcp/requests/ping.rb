# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class Ping < Base
        def call
          client.request(ping_request)
        end

        def ping_request
          {
            jsonrpc: "2.0",
            method: "ping"
          }
        end
      end
    end
  end
end
