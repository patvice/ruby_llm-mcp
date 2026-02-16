# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      module Concerns
        # Provides action methods for elicitation request handlers
        module ElicitationActions
          attr_reader :elicitation

          protected

          # Accept the elicitation with structured response
          # @param response [Hash] the structured response data
          # @return [Hash] structured acceptance response
          def accept(response)
            { action: :accept, response: response }
          end

          # Reject the elicitation
          # @param reason [String] reason for rejection
          # @return [Hash] structured rejection response
          def reject(reason)
            { action: :reject, reason: reason }
          end

          # Cancel the elicitation
          # @param reason [String] reason for cancellation
          # @return [Hash] structured cancellation response
          def cancel(reason)
            { action: :cancel, reason: reason }
          end

          # Default action when timeout occurs
          def default_timeout_action
            reject("Elicitation timed out")
          end
        end
      end
    end
  end
end




