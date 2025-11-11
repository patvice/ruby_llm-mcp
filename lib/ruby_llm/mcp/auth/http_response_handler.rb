# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      # Utility class for handling HTTP responses in OAuth flows
      # Consolidates error handling and response parsing
      class HttpResponseHandler
        # Handle and parse a successful HTTP response
        # @param response [HTTPX::Response, HTTPX::ErrorResponse] HTTP response
        # @param context [String] description for error messages (e.g., "Token exchange")
        # @param expected_status [Integer, Array<Integer>] expected status code(s)
        # @return [Hash] parsed JSON response
        # @raise [Errors::TransportError] if response is an error or unexpected status
        def self.handle_response(response, context:, expected_status: 200)
          expected_statuses = Array(expected_status)

          # Handle HTTPX ErrorResponse (connection failures, timeouts, etc.)
          if response.is_a?(HTTPX::ErrorResponse)
            error_message = response.error&.message || "Request failed"
            raise Errors::TransportError.new(
              message: "#{context} failed: #{error_message}"
            )
          end

          unless expected_statuses.include?(response.status)
            raise Errors::TransportError.new(
              message: "#{context} failed: HTTP #{response.status}",
              code: response.status
            )
          end

          JSON.parse(response.body.to_s)
        end

        # Extract redirect URI mismatch details from error response
        # @param body [String] error response body
        # @return [Hash, nil] mismatch details or nil
        def self.extract_redirect_mismatch(body)
          data = JSON.parse(body)
          error = data["error"] || data[:error]
          return nil unless error == "unauthorized_client"

          description = data["error_description"] || data[:error_description]
          return nil unless description.is_a?(String)

          # Parse common OAuth error message format
          # Matches: "You sent <url> and we expected <url>"
          match = description.match(%r{You sent\s+(https?://[^\s,]+)[\s,]+and we expected\s+(https?://\S+?)\.?\s*$}i)
          return nil unless match

          {
            sent: match[1],
            expected: match[2],
            description: description
          }
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
