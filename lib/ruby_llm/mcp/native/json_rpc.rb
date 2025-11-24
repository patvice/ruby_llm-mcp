# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module JsonRpc
        VERSION = "2.0"

        module ErrorCodes
          PARSE_ERROR = -32_700
          INVALID_REQUEST = -32_600
          METHOD_NOT_FOUND = -32_601
          INVALID_PARAMS = -32_602
          INTERNAL_ERROR = -32_603

          SERVER_ERROR_MIN = -32_099
          SERVER_ERROR_MAX = -32_000

          SERVER_ERROR = -32_000
        end

        class EnvelopeValidator
          attr_reader :envelope, :errors

          def initialize(envelope)
            @envelope = envelope
            @errors = []
          end

          def valid?
            validate!
            @errors.empty?
          end

          def error_message
            @errors.join("; ") if @errors.any?
          end

          def notification?
            !envelope.key?("id") && envelope.key?("method")
          end

          def request?
            envelope.key?("id") && envelope.key?("method") &&
              !envelope.key?("result") && !envelope.key?("error")
          end

          def response?
            envelope.key?("id") && !envelope.key?("method") &&
              (envelope.key?("result") || envelope.key?("error"))
          end

          private

          def validate!
            @errors = []

            unless envelope.is_a?(Hash)
              @errors << "Envelope must be an object"
              return
            end

            unless envelope["jsonrpc"] == VERSION
              @errors << "Missing or invalid 'jsonrpc' field (must be '#{VERSION}')"
            end

            # Determine message type and validate
            # Priority: response > request > notification (to catch malformed messages)
            if envelope.key?("id") && (envelope.key?("result") || envelope.key?("error"))
              validate_response!
            elsif envelope.key?("id") && envelope.key?("method")
              validate_request!
            elsif !envelope.key?("id") && envelope.key?("method")
              validate_notification!
            else
              @errors << "Message must be a request, response, or notification"
            end
          end

          def validate_notification!
            unless envelope["method"].is_a?(String) && !envelope["method"].empty?
              @errors << "Notification must have a non-empty 'method' string"
            end

            if envelope.key?("id")
              @errors << "Notification must not have 'id' field"
            end

            if envelope.key?("params") && !structured_value?(envelope["params"])
              @errors << "Notification 'params' must be an object or array"
            end
          end

          def validate_request!
            unless envelope["method"].is_a?(String) && !envelope["method"].empty?
              @errors << "Request must have a non-empty 'method' string"
            end

            unless valid_id?(envelope["id"])
              @errors << "Request 'id' must be a string, number, or null"
            end

            if envelope.key?("params") && !structured_value?(envelope["params"])
              @errors << "Request 'params' must be an object or array"
            end

            if envelope.key?("result") || envelope.key?("error")
              @errors << "Request must not have 'result' or 'error' fields"
            end
          end

          def validate_response!
            unless valid_id?(envelope["id"])
              @errors << "Response 'id' must be a string, number, or null"
            end

            if envelope.key?("method")
              @errors << "Response must not have 'method' field"
            end

            has_result = envelope.key?("result")
            has_error = envelope.key?("error")

            if has_result && has_error
              @errors << "Response must have either 'result' or 'error', not both"
            elsif !has_result && !has_error
              @errors << "Response must have either 'result' or 'error'"
            end

            if has_error
              validate_error_object!(envelope["error"])
            end
          end

          def validate_error_object!(error)
            unless error.is_a?(Hash)
              @errors << "Error must be an object"
              return
            end

            unless error["code"].is_a?(Integer)
              @errors << "Error 'code' must be an integer"
            end

            unless error["message"].is_a?(String)
              @errors << "Error 'message' must be a string"
            end

            if error.key?("data") && !valid_data_value?(error["data"])
              @errors << "Error 'data' must be a valid JSON value"
            end
          end

          def valid_id?(id)
            id.is_a?(String) || id.is_a?(Numeric) || id.nil?
          end

          def structured_value?(value)
            value.is_a?(Hash) || value.is_a?(Array)
          end

          def valid_data_value?(value)
            value.is_a?(String) || value.is_a?(Numeric) || value.is_a?(TrueClass) ||
              value.is_a?(FalseClass) || value.nil? || value.is_a?(Hash) || value.is_a?(Array)
          end
        end
      end
    end
  end
end
