# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      module Flows
        # Orchestrates OAuth 2.1 Client Credentials flow
        # Used for application authentication without user interaction
        class ClientCredentialsFlow
          attr_reader :discoverer, :client_registrar, :token_manager, :storage, :logger

          def initialize(discoverer:, client_registrar:, token_manager:, storage:, logger:)
            @discoverer = discoverer
            @client_registrar = client_registrar
            @token_manager = token_manager
            @storage = storage
            @logger = logger
          end

          # Perform client credentials flow
          # @param server_url [String] MCP server URL
          # @param redirect_uri [String] redirect URI (used for registration only)
          # @param scope [String, nil] requested scope
          # @return [Token] access token
          def execute(server_url, redirect_uri, scope)
            logger.debug("Starting OAuth client credentials flow")

            # 1. Discover authorization server
            server_metadata = discoverer.discover(server_url)
            raise Errors::TransportError.new(message: "OAuth server discovery failed") unless server_metadata

            # 2. Register client (or get cached client) with client credentials grant
            client_info = client_registrar.get_or_register(
              server_url,
              server_metadata,
              :client_credentials,
              redirect_uri,
              scope
            )

            # 3. Validate that we have a client secret
            unless client_info.client_secret
              raise Errors::TransportError.new(
                message: "Client credentials flow requires client_secret"
              )
            end

            # 4. Exchange client credentials for token
            token = token_manager.exchange_client_credentials(
              server_metadata,
              client_info,
              scope,
              server_url
            )

            # 5. Store token
            storage.set_token(server_url, token)

            logger.info("Client credentials authentication completed successfully")
            token
          end
        end
      end
    end
  end
end
