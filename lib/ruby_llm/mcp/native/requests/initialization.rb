# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Requests
        class Initialization
          def initialize(coordinator)
            @coordinator = coordinator
          end

          def call
            @coordinator.request(initialize_body)
          end

          def initialize_body
            {
              jsonrpc: "2.0",
              method: "initialize",
              params: {
                protocolVersion: @coordinator.protocol_version,
                capabilities: @coordinator.client_capabilities,
                clientInfo: {
                  name: "RubyLLM-MCP Client",
                  version: RubyLLM::MCP::VERSION
                }
              }
            }
          end
        end
      end
    end
  end
end
