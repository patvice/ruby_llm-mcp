# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      # Service for discovering OAuth authorization servers
      # Implements RFC 8414 (Server Metadata) and RFC 9728 (Protected Resource Metadata)
      class Discoverer
        attr_reader :http_client, :storage, :logger

        def initialize(http_client, storage, logger)
          @http_client = http_client
          @storage = storage
          @logger = logger
        end

        # Discover OAuth authorization server
        # Tries two patterns: server as own auth server, or delegated auth server
        # @param server_url [String] MCP server URL
        # @return [ServerMetadata, nil] server metadata or nil
        def discover(server_url)
          logger.debug("Discovering OAuth authorization server for #{server_url}")

          # Check cache first
          cached = storage.get_server_metadata(server_url)
          return cached if cached

          server_metadata = try_authorization_server_discovery(server_url) ||
                            try_protected_resource_discovery(server_url) ||
                            create_default_metadata(server_url)

          # Cache and return
          storage.set_server_metadata(server_url, server_metadata) if server_metadata
          server_metadata
        end

        private

        # Try oauth-authorization-server discovery (server is own auth server)
        # @param server_url [String] MCP server URL
        # @return [ServerMetadata, nil] server metadata or nil
        def try_authorization_server_discovery(server_url)
          discovery_url = UrlBuilder.build_discovery_url(server_url, :authorization_server)
          logger.debug("Trying discovery URL: #{discovery_url}")
          fetch_server_metadata(discovery_url)
        rescue StandardError => e
          logger.debug("oauth-authorization-server discovery failed: #{e.message}")
          nil
        end

        # Try oauth-protected-resource discovery (delegation pattern)
        # @param server_url [String] MCP server URL
        # @return [ServerMetadata, nil] server metadata or nil
        def try_protected_resource_discovery(server_url)
          discovery_url = UrlBuilder.build_discovery_url(server_url, :protected_resource)
          logger.debug("Trying protected resource discovery: #{discovery_url}")
          resource_metadata = fetch_resource_metadata(discovery_url)
          auth_server_url = resource_metadata.authorization_servers.first

          if auth_server_url
            logger.debug("Found delegated auth server: #{auth_server_url}")
            fetch_server_metadata("#{auth_server_url}/.well-known/oauth-authorization-server")
          end
        rescue StandardError => e
          logger.debug("oauth-protected-resource discovery failed: #{e.message}")
          nil
        end

        # Create default server metadata when discovery fails
        # @param server_url [String] MCP server URL
        # @return [ServerMetadata] server metadata with default endpoints
        def create_default_metadata(server_url)
          base_url = UrlBuilder.get_authorization_base_url(server_url)
          logger.warn("OAuth discovery failed, falling back to default endpoints")
          logger.info("Using default OAuth endpoints for #{base_url}")

          ServerMetadata.new(
            issuer: base_url,
            authorization_endpoint: "#{base_url}/authorize",
            token_endpoint: "#{base_url}/token",
            options: { registration_endpoint: "#{base_url}/register" }
          )
        end

        # Fetch OAuth server metadata
        # @param url [String] discovery URL
        # @return [ServerMetadata] server metadata
        def fetch_server_metadata(url)
          logger.debug("Fetching server metadata from #{url}")
          response = http_client.get(url)

          data = HttpResponseHandler.handle_response(response, context: "Server metadata fetch")

          ServerMetadata.new(
            issuer: data["issuer"],
            authorization_endpoint: data["authorization_endpoint"],
            token_endpoint: data["token_endpoint"],
            options: {
              registration_endpoint: data["registration_endpoint"],
              scopes_supported: data["scopes_supported"],
              response_types_supported: data["response_types_supported"],
              grant_types_supported: data["grant_types_supported"]
            }
          )
        end

        # Fetch OAuth protected resource metadata
        # @param url [String] discovery URL
        # @return [ResourceMetadata] resource metadata
        def fetch_resource_metadata(url)
          logger.debug("Fetching resource metadata from #{url}")
          response = http_client.get(url)

          data = HttpResponseHandler.handle_response(response, context: "Resource metadata fetch")

          ResourceMetadata.new(
            resource: data["resource"],
            authorization_servers: data["authorization_servers"]
          )
        end
      end
    end
  end
end
