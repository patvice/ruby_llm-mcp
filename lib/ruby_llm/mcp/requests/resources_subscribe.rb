# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class ResourcesSubscribe
        def initialize(coordinator, uri:)
          @coordinator = coordinator
          @uri = uri
        end

        def call
          @coordinator.request(resources_subscribe_body, wait_for_response: false)
        end

        private

        def resources_subscribe_body
          {
            jsonrpc: "2.0",
            method: "resources/subscribe",
            params: {
              uri: @uri
            }
          }
        end
      end
    end
  end
end
