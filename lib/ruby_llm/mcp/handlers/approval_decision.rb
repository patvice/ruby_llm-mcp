# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      # Normalized decision returned by human-in-the-loop handlers.
      class ApprovalDecision
        VALID_STATUSES = %i[approved denied deferred].freeze

        attr_reader :status, :reason, :approval_id, :timeout, :promise

        def initialize(status:, reason: nil, approval_id: nil, timeout: nil, promise: nil)
          @status = status.to_sym
          @reason = reason
          @approval_id = approval_id
          @timeout = timeout
          @promise = promise
        end

        def self.approved
          new(status: :approved)
        end

        def self.denied(reason: "Denied by user")
          new(status: :denied, reason: reason)
        end

        def self.deferred(approval_id:, timeout:)
          new(status: :deferred, approval_id: approval_id, timeout: timeout)
        end

        def self.from_handler_result(result, approval_id:, default_timeout: nil)
          unless result.is_a?(Hash)
            raise Errors::InvalidApprovalDecision.new(
              message: "Human-in-the-loop handler must return a Hash, got #{result.class}"
            )
          end

          status = (result[:status] || result["status"])&.to_sym
          unless VALID_STATUSES.include?(status)
            raise Errors::InvalidApprovalDecision.new(
              message: "Human-in-the-loop handler returned invalid status '#{status.inspect}'"
            )
          end

          case status
          when :approved
            approved
          when :denied
            denied(reason: result[:reason] || result["reason"] || "Denied by user")
          when :deferred
            timeout = result[:timeout] || result["timeout"] || default_timeout
            validate_timeout!(timeout)
            deferred(approval_id: approval_id, timeout: timeout.to_f)
          end
        end

        def with_promise(promise)
          self.class.new(
            status: status,
            reason: reason,
            approval_id: approval_id,
            timeout: timeout,
            promise: promise
          )
        end

        def approved?
          status == :approved
        end

        def denied?
          status == :denied
        end

        def deferred?
          status == :deferred
        end

        private_class_method def self.validate_timeout!(timeout)
          unless timeout.is_a?(Numeric) && timeout.positive?
            raise Errors::InvalidApprovalDecision.new(
              message: "Deferred approvals require a positive timeout"
            )
          end
        end
      end
    end
  end
end
