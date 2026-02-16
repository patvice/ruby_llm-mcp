# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      module Concerns
        # Provides action methods for human-in-the-loop approval handlers
        module ApprovalActions
          attr_reader :approval_id, :tool_name, :parameters

          protected

          # Approve the tool execution
          # @return [Hash] structured approval response
          def approve
            { status: :approved }
          end

          # Deny the tool execution
          # @param reason [String] reason for denial
          # @return [Hash] structured denial response
          def deny(reason = "Denied by user")
            { status: :denied, reason: reason }
          end

          # Defer approval to complete asynchronously via registry.
          # @param timeout [Numeric, nil] timeout in seconds; falls back to handler timeout
          # @return [Hash] structured deferred response
          def defer(timeout: nil)
            resolved_timeout = timeout || (respond_to?(:timeout) ? self.timeout : nil)
            { status: :deferred, timeout: resolved_timeout }
          end

          # Override guard_failed to return denial (if GuardChecks is included)
          def guard_failed(message)
            deny(message)
          end
        end
      end
    end
  end
end
