# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Responses
        class RootsList
          def initialize(coordinator, id:)
            @coordinator = coordinator
            @id = id
          end

          def call
            @coordinator.request(roots_list_body, add_id: false, wait_for_response: false)
          end

          private

          def roots_list_body
            roots_response = @coordinator.roots_paths.map do |path|
              {
                uri: "file://#{path}",
                name: File.basename(path, ".*")
              }
            end

            {
              jsonrpc: "2.0",
              id: @id,
              result: {
                roots: roots_response
              }
            }
          end
        end
      end
    end
  end
end
