# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      # Service for managing OAuth token operations
      # Handles token exchange, refresh, and client credentials flows
      class TokenManager
        attr_reader :http_client, :logger

        def initialize(http_client, logger)
          @http_client = http_client
          @logger = logger
        end

        # Exchange authorization code for access token
        # @param server_metadata [ServerMetadata] server metadata
        # @param client_info [ClientInfo] client info
        # @param code [String] authorization code
        # @param pkce [PKCE] PKCE parameters
        # @param server_url [String] MCP server URL
        # @return [Token] access token
        def exchange_authorization_code(server_metadata, client_info, code, pkce, server_url)
          logger.debug("Exchanging authorization code for access token")

          registered_redirect_uri = client_info.metadata.redirect_uris.first
          params = build_auth_code_params(client_info, code, pkce, registered_redirect_uri, server_url)

          response = post_token_exchange(server_metadata, params)
          response = retry_if_redirect_mismatch(response, server_metadata, params, registered_redirect_uri)

          validate_token_response!(response, "Token exchange")
          parse_token_response(response)
        end

        # Exchange client credentials for access token
        # @param server_metadata [ServerMetadata] server metadata
        # @param client_info [ClientInfo] client info with secret
        # @param scope [String, nil] requested scope
        # @param server_url [String] MCP server URL
        # @return [Token] access token
        def exchange_client_credentials(server_metadata, client_info, scope, server_url)
          logger.debug("Exchanging client credentials for access token")

          params = {
            grant_type: "client_credentials",
            client_id: client_info.client_id,
            client_secret: client_info.client_secret,
            scope: scope,
            resource: server_url
          }.compact

          response = post_token_exchange(server_metadata, params)
          validate_token_response!(response, "Token exchange")
          parse_token_response(response)
        end

        # Refresh access token using refresh token
        # @param server_metadata [ServerMetadata] server metadata
        # @param client_info [ClientInfo] client info
        # @param token [Token] current token with refresh_token
        # @param server_url [String] MCP server URL
        # @return [Token, nil] new token or nil if refresh failed
        def refresh_token(server_metadata, client_info, token, server_url)
          return nil unless token.refresh_token

          logger.debug("Refreshing access token")

          params = build_refresh_params(client_info, token, server_url)
          response = post_token_refresh(server_metadata, params)

          # Return nil on error responses
          return nil if response.is_a?(HTTPX::ErrorResponse)

          if response.status != 200
            oauth_error = extract_oauth_error(response.body.to_s)
            raise_oauth_error!("Token refresh", oauth_error, response.status) if oauth_error
            return nil
          end

          parse_refresh_response(response, token)
        rescue Errors::TransportError => e
          logger.warn(e.message)
          nil
        rescue JSON::ParserError => e
          logger.warn("Invalid token refresh response: #{e.message}")
          nil
        rescue HTTPX::Error => e
          logger.warn("Network error during token refresh: #{e.message}")
          nil
        end

        private

        # Build parameters for authorization code exchange
        # @param client_info [ClientInfo] client info
        # @param code [String] authorization code
        # @param pkce [PKCE] PKCE parameters
        # @param redirect_uri [String] redirect URI
        # @param server_url [String] MCP server URL
        # @return [Hash] token exchange parameters
        def build_auth_code_params(client_info, code, pkce, redirect_uri, server_url)
          params = {
            grant_type: "authorization_code",
            code: code,
            redirect_uri: redirect_uri,
            client_id: client_info.client_id,
            code_verifier: pkce.code_verifier,
            resource: server_url
          }

          add_client_secret_if_needed(params, client_info)
          params
        end

        # Build parameters for token refresh
        # @param client_info [ClientInfo] client info
        # @param token [Token] current token
        # @param server_url [String] MCP server URL
        # @return [Hash] refresh parameters
        def build_refresh_params(client_info, token, server_url)
          params = {
            grant_type: "refresh_token",
            refresh_token: token.refresh_token,
            client_id: client_info.client_id,
            resource: server_url
          }

          add_client_secret_if_needed(params, client_info)
          params
        end

        # Add client secret to params if needed
        # @param params [Hash] token request parameters
        # @param client_info [ClientInfo] client info
        def add_client_secret_if_needed(params, client_info)
          return unless client_info.client_secret
          return unless client_info.metadata.token_endpoint_auth_method == "client_secret_post"

          params[:client_secret] = client_info.client_secret
        end

        # Post token exchange request
        # @param server_metadata [ServerMetadata] server metadata
        # @param params [Hash] form parameters
        # @return [HTTPX::Response] HTTP response
        def post_token_exchange(server_metadata, params)
          http_client.post(
            server_metadata.token_endpoint,
            headers: { "Content-Type" => "application/x-www-form-urlencoded" },
            form: params
          )
        end

        # Post token refresh request
        # @param server_metadata [ServerMetadata] server metadata
        # @param params [Hash] form parameters
        # @return [HTTPX::Response] HTTP response
        def post_token_refresh(server_metadata, params)
          response = http_client.post(
            server_metadata.token_endpoint,
            headers: { "Content-Type" => "application/x-www-form-urlencoded" },
            form: params
          )

          if response.is_a?(HTTPX::ErrorResponse)
            logger.warn("Token refresh failed: #{response.error&.message || 'Request failed'}")
          elsif response.status != 200
            logger.warn("Token refresh failed: HTTP #{response.status}")
          end
          response
        end

        # Retry token exchange if redirect URI mismatch detected
        # @param response [HTTPX::Response] initial response
        # @param server_metadata [ServerMetadata] server metadata
        # @param params [Hash] exchange parameters
        # @param registered_redirect_uri [String] registered redirect URI
        # @return [HTTPX::Response] response (possibly retried)
        def retry_if_redirect_mismatch(response, server_metadata, params, registered_redirect_uri)
          # Don't retry on error responses
          return response if response.is_a?(HTTPX::ErrorResponse)
          return response if response.status == 200

          redirect_hint = HttpResponseHandler.extract_redirect_mismatch(response.body.to_s)
          return response unless redirect_hint
          return response if redirect_hint[:expected] == registered_redirect_uri

          logger.warn("Redirect URI mismatch, retrying with: #{redirect_hint[:expected]}")
          params[:redirect_uri] = redirect_hint[:expected]
          post_token_exchange(server_metadata, params)
        end

        # Validate token response
        # @param response [HTTPX::Response, HTTPX::ErrorResponse] HTTP response
        # @param context [String] context for error messages
        # @raise [Errors::TransportError] if response is invalid
        def validate_token_response!(response, context)
          # Handle HTTPX ErrorResponse
          if response.is_a?(HTTPX::ErrorResponse)
            error_message = response.error&.message || "Request failed"
            raise Errors::TransportError.new(message: "#{context} failed: #{error_message}")
          end

          oauth_error = extract_oauth_error(response.body.to_s)
          raise_oauth_error!(context, oauth_error, response.status) if oauth_error

          return if response.status == 200

          raise Errors::TransportError.new(
            message: "#{context} failed: HTTP #{response.status}",
            code: response.status
          )
        end

        # Parse token response
        # @param response [HTTPX::Response] HTTP response
        # @return [Token] parsed token
        def parse_token_response(response)
          data = JSON.parse(response.body.to_s)
          raise_oauth_error!("Token exchange", extract_oauth_error(data), response.status)

          access_token = data["access_token"]
          if access_token.nil? || access_token.empty?
            raise Errors::TransportError.new(
              message: "Token exchange failed: invalid token response (missing access_token)",
              code: response.status
            )
          end

          Token.new(
            access_token: access_token,
            token_type: data["token_type"] || "Bearer",
            expires_in: data["expires_in"],
            scope: data["scope"],
            refresh_token: data["refresh_token"]
          )
        end

        # Parse refresh response, preserving old refresh token if not provided
        # @param response [HTTPX::Response] HTTP response
        # @param old_token [Token] previous token
        # @return [Token] new token
        def parse_refresh_response(response, old_token)
          data = JSON.parse(response.body.to_s)
          raise_oauth_error!("Token refresh", extract_oauth_error(data), response.status)

          access_token = data["access_token"]
          if access_token.nil? || access_token.empty?
            raise Errors::TransportError.new(
              message: "Token refresh failed: invalid token response (missing access_token)",
              code: response.status
            )
          end

          Token.new(
            access_token: access_token,
            token_type: data["token_type"] || "Bearer",
            expires_in: data["expires_in"],
            scope: data["scope"],
            refresh_token: data["refresh_token"] || old_token.refresh_token
          )
        end

        # Extract OAuth error fields from JSON response data
        # @param source [String, Hash] response body string or parsed JSON hash
        # @return [Hash, nil] OAuth error fields or nil
        def extract_oauth_error(source)
          data = source.is_a?(Hash) ? source : JSON.parse(source)
          error = data["error"] || data[:error]
          return nil unless error

          {
            error: error,
            error_description: data["error_description"] || data[:error_description],
            error_uri: data["error_uri"] || data[:error_uri]
          }
        rescue JSON::ParserError
          nil
        end

        # Raise TransportError for OAuth error responses
        # @param context [String] context for the error
        # @param oauth_error [Hash, nil] OAuth error fields
        # @param status_code [Integer, nil] HTTP response status code
        # @raise [Errors::TransportError] when oauth_error is present
        def raise_oauth_error!(context, oauth_error, status_code)
          return unless oauth_error

          error = oauth_error[:error]
          description = oauth_error[:error_description]
          error_uri = oauth_error[:error_uri]

          message = "#{context} failed: OAuth error '#{error}'"
          message += ": #{description}" if description
          message += " (#{error_uri})" if error_uri

          raise Errors::TransportError.new(
            message: message,
            code: status_code,
            error: error
          )
        end
      end
    end
  end
end
