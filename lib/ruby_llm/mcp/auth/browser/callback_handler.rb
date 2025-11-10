# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      module Browser
        # Handles OAuth callback request processing
        # Extracts and validates OAuth parameters from callback requests
        class CallbackHandler
          attr_reader :callback_path, :logger

          def initialize(callback_path:, logger: nil)
            @callback_path = callback_path
            @logger = logger || MCP.logger
          end

          # Validate that the request path matches the expected callback path
          # @param path [String] request path
          # @return [Boolean] true if path is valid
          def valid_callback_path?(path)
            uri_path, = path.split("?", 2)
            uri_path == @callback_path
          end

          # Parse callback parameters from path
          # @param path [String] full request path with query string
          # @param http_server [HttpServer] HTTP server instance for parsing
          # @return [Hash] parsed parameters
          def parse_callback_params(path, http_server)
            _, query_string = path.split("?", 2)
            params = http_server.parse_query_params(query_string || "")
            @logger.debug("Callback params: #{params.keys.join(', ')}")
            params
          end

          # Extract OAuth parameters from parsed params
          # @param params [Hash] parsed query parameters
          # @return [Hash] OAuth parameters (code, state, error, error_description)
          def extract_oauth_params(params)
            {
              code: params["code"],
              state: params["state"],
              error: params["error"],
              error_description: params["error_description"]
            }
          end

          # Update result hash with OAuth parameters (thread-safe)
          # @param oauth_params [Hash] OAuth parameters
          # @param result [Hash] result container
          # @param mutex [Mutex] synchronization mutex
          # @param condition [ConditionVariable] wait condition
          def update_result_with_oauth_params(oauth_params, result, mutex, condition)
            mutex.synchronize do
              if oauth_params[:error]
                result[:error] = oauth_params[:error_description] || oauth_params[:error]
              elsif oauth_params[:code] && oauth_params[:state]
                result[:code] = oauth_params[:code]
                result[:state] = oauth_params[:state]
              else
                result[:error] = "Invalid callback: missing code or state parameter"
              end
              result[:completed] = true
              condition.signal
            end
          end
        end
      end
    end
  end
end
