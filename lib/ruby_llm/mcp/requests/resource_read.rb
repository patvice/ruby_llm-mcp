# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      class ResourceRead
        attr_reader :client, :uri

        def initialize(client, uri:)
          @client = client
          @uri = uri
        end

        def call
          client.request(reading_resource_body(uri))
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
