# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class ResourceRead
        attr_reader :coordinator, :uri

        def initialize(coordinator, uri:)
          @coordinator = coordinator
          @uri = uri
        end

        def call
          coordinator.request(reading_resource_body(uri))
        end

        def reading_resource_body(uri)
          {
            jsonrpc: "2.0",
            method: "resources/read",
            params: {
              uri: uri
            }
          }
        end
      end
    end
  end
end
