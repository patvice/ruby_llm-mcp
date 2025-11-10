# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      module Flows
        # Orchestrates OAuth 2.1 Authorization Code flow with PKCE
        # Coordinates session management, discovery, registration, and token exchange
        class AuthorizationCodeFlow
          attr_reader :discoverer, :client_registrar, :session_manager, :token_manager, :storage, :logger

          def initialize(discoverer:, client_registrar:, session_manager:, token_manager:, storage:, logger:) # rubocop:disable Metrics/ParameterLists
            @discoverer = discoverer
            @client_registrar = client_registrar
            @session_manager = session_manager
            @token_manager = token_manager
            @storage = storage
            @logger = logger
          end

          # Start OAuth authorization flow
          # @param server_url [String] MCP server URL
          # @param redirect_uri [String] redirect URI for callback
          # @param scope [String, nil] requested scope
          # @param https_validator [Proc] callback to validate HTTPS usage
          # @return [String] authorization URL for user to visit
          def start(server_url, redirect_uri, scope, https_validator: nil)
            logger.debug("Starting OAuth authorization flow for #{server_url}")

            # 1. Discover authorization server
            server_metadata = discoverer.discover(server_url)
            raise Errors::TransportError.new(message: "OAuth server discovery failed") unless server_metadata

            # 2. Register client (or get cached client)
            client_info = client_registrar.get_or_register(
              server_url,
              server_metadata,
              :authorization_code,
              redirect_uri,
              scope
            )

            # 3. Create session with PKCE and CSRF state
            session = session_manager.create_session(server_url)

            # 4. Validate HTTPS usage (optional warning)
            https_validator&.call(server_metadata.authorization_endpoint, "Authorization endpoint")

            # 5. Build and return authorization URL
            auth_url = UrlBuilder.build_authorization_url(
              server_metadata.authorization_endpoint,
              client_info.client_id,
              client_info.metadata.redirect_uris.first,
              scope,
              session[:state],
              session[:pkce],
              server_url
            )

            logger.debug("Authorization URL: #{auth_url}")
            auth_url
          end

          # Complete OAuth authorization flow after callback
          # @param server_url [String] MCP server URL
          # @param code [String] authorization code from callback
          # @param state [String] state parameter from callback
          # @return [Token] access token
          def complete(server_url, code, state)
            logger.debug("Completing OAuth authorization flow")

            # 1. Validate state and retrieve session data
            session_data = session_manager.validate_and_retrieve_session(server_url, state)

            pkce = session_data[:pkce]
            client_info = session_data[:client_info]
            server_metadata = discoverer.discover(server_url)

            unless pkce && client_info
              raise Errors::TransportError.new(message: "Missing PKCE or client info")
            end

            # 2. Exchange authorization code for tokens
            token = token_manager.exchange_authorization_code(
              server_metadata,
              client_info,
              code,
              pkce,
              server_url
            )

            # 3. Store token
            storage.set_token(server_url, token)

            # 4. Clean up temporary session data
            session_manager.cleanup_session(server_url)

            logger.info("OAuth authorization completed successfully")
            token
          end
        end
      end
    end
  end
end
