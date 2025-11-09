# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      # Service for registering OAuth clients
      # Implements RFC 7591 (Dynamic Client Registration)
      class ClientRegistrar
        attr_reader :http_client, :storage, :logger, :config

        def initialize(http_client, storage, logger, config)
          @http_client = http_client
          @storage = storage
          @logger = logger
          @config = config
        end

        # Get cached client info or register new client
        # @param server_url [String] MCP server URL
        # @param server_metadata [ServerMetadata] server metadata
        # @param grant_type [Symbol] :authorization_code or :client_credentials
        # @param redirect_uri [String] redirect URI for authorization code flow
        # @param scope [String, nil] requested scope
        # @return [ClientInfo] client information
        def get_or_register(server_url, server_metadata, grant_type, redirect_uri, scope)
          # Check cache first
          client_info = storage.get_client_info(server_url)
          return client_info if client_info && !client_info.client_secret_expired?

          # Register new client if no cached info or secret expired
          if server_metadata.supports_registration?
            register(server_url, server_metadata, grant_type, redirect_uri, scope)
          else
            raise Errors::TransportError.new(
              message: "OAuth server does not support dynamic client registration"
            )
          end
        end

        # Register OAuth client dynamically (RFC 7591)
        # @param server_url [String] MCP server URL
        # @param server_metadata [ServerMetadata] server metadata
        # @param grant_type [Symbol] :authorization_code or :client_credentials
        # @param redirect_uri [String] redirect URI for authorization code flow
        # @param scope [String, nil] requested scope
        # @return [ClientInfo] registered client info
        def register(server_url, server_metadata, grant_type, redirect_uri, scope)
          logger.debug("Registering OAuth client at: #{server_metadata.registration_endpoint}")

          metadata = build_client_metadata(grant_type, redirect_uri, scope)
          response = post_registration(server_metadata, metadata)
          data = HttpResponseHandler.handle_response(response, context: "Client registration",
                                                               expected_status: [200, 201])

          registered_metadata = parse_registered_metadata(data, redirect_uri)
          warn_redirect_uri_mismatch(registered_metadata, redirect_uri)

          client_info = create_client_info(data, registered_metadata)
          storage.set_client_info(server_url, client_info)
          logger.debug("Client registered successfully: #{client_info.client_id}")
          client_info
        end

        private

        # Build client metadata for registration request
        # @param grant_type [Symbol] :authorization_code or :client_credentials
        # @param redirect_uri [String] redirect URI
        # @param scope [String, nil] requested scope
        # @return [ClientMetadata] client metadata
        def build_client_metadata(grant_type, redirect_uri, scope)
          strategy = grant_strategy_for(grant_type)

          metadata = {
            redirect_uris: [redirect_uri],
            token_endpoint_auth_method: strategy.auth_method,
            grant_types: strategy.grant_types_list,
            response_types: strategy.response_types_list,
            scope: scope,
            client_name: config.oauth.client_name,
            client_uri: config.oauth.client_uri,
            logo_uri: config.oauth.logo_uri,
            contacts: config.oauth.contacts,
            tos_uri: config.oauth.tos_uri,
            policy_uri: config.oauth.policy_uri,
            jwks_uri: config.oauth.jwks_uri,
            jwks: config.oauth.jwks,
            software_id: config.oauth.software_id,
            software_version: config.oauth.software_version
          }.compact

          ClientMetadata.new(**metadata)
        end

        # Get grant strategy for grant type
        # @param grant_type [Symbol] :authorization_code or :client_credentials
        # @return [GrantStrategies::Base] grant strategy
        def grant_strategy_for(grant_type)
          case grant_type
          when :client_credentials
            GrantStrategies::ClientCredentials.new
          else
            GrantStrategies::AuthorizationCode.new
          end
        end

        # Post client registration request
        # @param server_metadata [ServerMetadata] server metadata
        # @param metadata [ClientMetadata] client metadata
        # @return [HTTPX::Response] HTTP response
        def post_registration(server_metadata, metadata)
          http_client.post(
            server_metadata.registration_endpoint,
            headers: { "Content-Type" => "application/json" },
            json: metadata.to_h
          )
        end

        # Parse registered client metadata from response
        # @param data [Hash] registration response data
        # @param redirect_uri [String] requested redirect URI
        # @return [ClientMetadata] registered metadata
        def parse_registered_metadata(data, redirect_uri)
          ClientMetadata.new(
            redirect_uris: data["redirect_uris"] || [redirect_uri],
            token_endpoint_auth_method: data["token_endpoint_auth_method"] || "none",
            grant_types: data["grant_types"] || %w[authorization_code refresh_token],
            response_types: data["response_types"] || ["code"],
            scope: data["scope"],
            client_name: data["client_name"],
            client_uri: data["client_uri"],
            logo_uri: data["logo_uri"],
            contacts: data["contacts"],
            tos_uri: data["tos_uri"],
            policy_uri: data["policy_uri"],
            jwks_uri: data["jwks_uri"],
            jwks: data["jwks"],
            software_id: data["software_id"],
            software_version: data["software_version"]
          )
        end

        # Warn if server changed redirect URI
        # @param registered_metadata [ClientMetadata] registered metadata
        # @param redirect_uri [String] requested redirect URI
        def warn_redirect_uri_mismatch(registered_metadata, redirect_uri)
          return if registered_metadata.redirect_uris.first == redirect_uri

          logger.warn("OAuth server changed redirect_uri:")
          logger.warn("  Requested:  #{redirect_uri}")
          logger.warn("  Registered: #{registered_metadata.redirect_uris.first}")
        end

        # Create client info from registration response
        # @param data [Hash] registration response data
        # @param registered_metadata [ClientMetadata] registered metadata
        # @return [ClientInfo] client info
        def create_client_info(data, registered_metadata)
          ClientInfo.new(
            client_id: data["client_id"],
            client_secret: data["client_secret"],
            client_id_issued_at: data["client_id_issued_at"],
            client_secret_expires_at: data["client_secret_expires_at"],
            metadata: registered_metadata
          )
        end
      end
    end
  end
end
