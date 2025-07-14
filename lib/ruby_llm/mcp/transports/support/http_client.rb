# frozen_string_literal: true

require "httpx"

module RubyLLM
  module MCP
    module Transports
      module Support
        class HTTPClient
          CONNECTION_KEY = :ruby_llm_mcp_client_connection

          def self.connection
            Thread.current[CONNECTION_KEY] ||= build_connection
          end

          def self.build_connection
            HTTPX.with(
              pool_options: {
                max_connections: RubyLLM::MCP.config.max_connections,
                pool_timeout: RubyLLM::MCP.config.pool_timeout
              }
            )
          end
        end
      end
    end
  end
end
