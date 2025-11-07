# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Requests
        class CompletionResource
          def initialize(coordinator, uri:, argument:, value:, context: nil)
            @coordinator = coordinator
            @uri = uri
            @argument = argument
            @value = value
            @context = context
          end

          def call
            @coordinator.request(request_body)
          end

          private

          def request_body
            {
              jsonrpc: "2.0",
              id: 1,
              method: "completion/complete",
              params: {
                ref: {
                  type: "ref/resource",
                  uri: @uri
                },
                argument: {
                  name: @argument,
                  value: @value
                },
                context: format_context
              }.compact
            }
          end

          def format_context
            return nil if @context.nil?

            {
              arguments: @context
            }
          end
        end
      end
    end
  end
end
