# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Responses
        class Error
          def initialize(coordinator, id:, message:, code: -32_000)
            @coordinator = coordinator
            @id = id
            @message = message
            @code = code
          end

          def call
            @coordinator.request(sampling_error_body, add_id: false, wait_for_response: false)
          end

          private

          def sampling_error_body
            {
              jsonrpc: "2.0",
              id: @id,
              error: {
                code: @code,
                message: @message
              }
            }
          end
        end
      end
    end
  end
end
