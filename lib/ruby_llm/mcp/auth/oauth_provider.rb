# frozen_string_literal: true

require "cgi"
require "httpx"
require "json"
require "uri"
require_relative "../auth"

module RubyLLM
  module MCP
    module Auth
      # Core OAuth 2.1 provider implementing complete authorization flow
      # Supports RFC 7636 (PKCE), RFC 7591 (Dynamic Registration),
      # RFC 8414 (Server Metadata), RFC 8707 (Resource Indicators), RFC 9728 (Protected Resource Metadata)
      class OAuthProvider
        attr_reader :server_url
        attr_accessor :redirect_uri, :scope, :logger, :storage

        def initialize(server_url:, redirect_uri: "http://localhost:8080/callback", scope: nil, logger: nil,
                       storage: nil)
          self.server_url = server_url # Normalizes URL
          self.redirect_uri = redirect_uri
          self.scope = scope
          self.logger = logger || MCP.logger
          self.storage = storage || MemoryStorage.new
          @http_client = create_http_client
        end

        # Get current access token, refreshing if needed
        # @return [Token, nil] valid access token or nil
        def access_token
          token = storage.get_token(server_url)
          logger.debug("OAuth access_token: retrieved token=#{token ? 'present' : 'nil'}")
          return nil unless token

          # Return token if still valid
          return token unless token.expired? || token.expires_soon?

          # Try to refresh if we have a refresh token
          refresh_token(token) if token.refresh_token
        end

        # Start OAuth authorization flow
        # @return [String] authorization URL for user to visit
        def start_authorization_flow
          logger.debug("Starting OAuth authorization flow for #{server_url}")

          # 1. Discover authorization server
          server_metadata = discover_authorization_server

          raise Errors::TransportError.new("OAuth server discovery failed", nil, nil) unless server_metadata

          # 2. Register client (or get cached client)
          client_info = get_or_register_client(server_metadata)

          # 3. Generate PKCE parameters
          pkce = PKCE.new
          storage.set_pkce(server_url, pkce)

          # 4. Generate CSRF protection state
          state = SecureRandom.urlsafe_base64(32)
          storage.set_state(server_url, state)

          # 5. Build and return authorization URL
          auth_url = build_authorization_url(server_metadata, client_info, pkce, state)
          logger.debug("Authorization URL: #{auth_url}")
          auth_url
        end

        # Complete OAuth authorization flow after callback
        # @param code [String] authorization code from callback
        # @param state [String] state parameter from callback
        # @return [Token] access token
        def complete_authorization_flow(code, state)
          logger.debug("Completing OAuth authorization flow")

          # 1. Verify CSRF state parameter
          stored_state = storage.get_state(server_url)
          raise ArgumentError, "Invalid state parameter" unless stored_state == state

          # 2. Retrieve PKCE and client info
          pkce = storage.get_pkce(server_url)
          client_info = storage.get_client_info(server_url)
          server_metadata = discover_authorization_server

          unless pkce && client_info
            raise Errors::TransportError.new("Missing PKCE or client info", nil, nil)
          end

          # 3. Exchange authorization code for tokens
          token = exchange_authorization_code(server_metadata, client_info, code, pkce)

          # 4. Store token
          storage.set_token(server_url, token)

          # 5. Clean up temporary data
          storage.delete_pkce(server_url)
          storage.delete_state(server_url)

          logger.info("OAuth authorization completed successfully")
          token
        end

        # Apply authorization header to HTTP request
        # @param request [HTTPX::Request] HTTP request object
        def apply_authorization(request)
          token = access_token
          logger.debug("OAuth apply_authorization: token=#{token ? 'present' : 'nil'}")
          return unless token

          logger.debug("OAuth applying authorization header: #{token.to_header[0..20]}...")
          request.headers["Authorization"] = token.to_header
        end

        private

        # Create HTTP client for OAuth requests
        # @return [HTTPX::Session] HTTP client
        def create_http_client
          HTTPX.plugin(:follow_redirects).with(
            timeout: { total: 30 },
            headers: {
              "Accept" => "application/json",
              "User-Agent" => "RubyLLM-MCP/#{RubyLLM::MCP::VERSION}"
            }
          )
        end

        # Normalize and set server URL
        # Ensures consistent URL format for storage keys
        def server_url=(url)
          @server_url = normalize_server_url(url)
        end

        # Normalize server URL for consistent comparison
        # @param url [String] raw URL
        # @return [String] normalized URL
        def normalize_server_url(url)
          uri = URI.parse(url)

          # Lowercase scheme and host (case-insensitive per RFC)
          uri.scheme = uri.scheme&.downcase
          uri.host = uri.host&.downcase

          # Remove default ports
          if (uri.scheme == "http" && uri.port == 80) || (uri.scheme == "https" && uri.port == 443)
            uri.port = nil
          end

          # Normalize path
          if uri.path.nil? || uri.path.empty? || uri.path == "/"
            uri.path = ""
          elsif uri.path.end_with?("/")
            uri.path = uri.path.chomp("/")
          end

          # Remove fragment
          uri.fragment = nil

          uri.to_s
        end

        # Discover OAuth authorization server
        # Tries two patterns: server as own auth server, or delegated auth server
        # @return [ServerMetadata, nil] server metadata or nil
        def discover_authorization_server
          logger.debug("Discovering OAuth authorization server for #{server_url}")

          # Check cache first
          cached = storage.get_server_metadata(server_url)
          return cached if cached

          server_metadata = nil

          # 1. Try oauth-authorization-server (MCP spec - server is own auth server)
          begin
            discovery_url = build_discovery_url(server_url, :authorization_server)
            logger.debug("Trying discovery URL: #{discovery_url}")
            server_metadata = fetch_server_metadata(discovery_url)
          rescue StandardError => e
            logger.debug("oauth-authorization-server discovery failed: #{e.message}")
          end

          # 2. Fallback to oauth-protected-resource (delegation pattern)
          unless server_metadata
            begin
              discovery_url = build_discovery_url(server_url, :protected_resource)
              logger.debug("Trying protected resource discovery: #{discovery_url}")
              resource_metadata = fetch_resource_metadata(discovery_url)
              auth_server_url = resource_metadata.authorization_servers.first

              if auth_server_url
                logger.debug("Found delegated auth server: #{auth_server_url}")
                server_metadata = fetch_server_metadata(
                  "#{auth_server_url}/.well-known/oauth-authorization-server"
                )
              end
            rescue StandardError => e
              logger.debug("oauth-protected-resource discovery failed: #{e.message}")
            end
          end

          # Cache and return
          storage.set_server_metadata(server_url, server_metadata) if server_metadata
          server_metadata
        end

        # Build discovery URL for OAuth server metadata
        # @param server_url [String] MCP server URL
        # @param discovery_type [Symbol] :authorization_server or :protected_resource
        # @return [String] discovery URL
        def build_discovery_url(server_url, discovery_type = :authorization_server)
          uri = URI.parse(server_url)

          # Extract ONLY origin (scheme + host + port)
          origin = "#{uri.scheme}://#{uri.host}"
          origin += ":#{uri.port}" if uri.port && !default_port?(uri)

          # Two discovery endpoints supported
          endpoint = if discovery_type == :authorization_server
                       "oauth-authorization-server"
                     else
                       "oauth-protected-resource"
                     end

          "#{origin}/.well-known/#{endpoint}"
        end

        # Check if port is default for scheme
        # @param uri [URI] parsed URI
        # @return [Boolean] true if default port
        def default_port?(uri)
          (uri.scheme == "http" && uri.port == 80) ||
            (uri.scheme == "https" && uri.port == 443)
        end

        # Fetch OAuth server metadata
        # @param url [String] discovery URL
        # @return [ServerMetadata] server metadata
        def fetch_server_metadata(url)
          logger.debug("Fetching server metadata from #{url}")
          response = @http_client.get(url)

          unless response.status == 200
            raise Errors::TransportError.new("Server metadata fetch failed: HTTP #{response.status}", nil, nil)
          end

          data = JSON.parse(response.body.to_s)

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
          response = @http_client.get(url)

          unless response.status == 200
            raise Errors::TransportError.new("Resource metadata fetch failed: HTTP #{response.status}", nil, nil)
          end

          data = JSON.parse(response.body.to_s)

          ResourceMetadata.new(
            resource: data["resource"],
            authorization_servers: data["authorization_servers"]
          )
        end

        # Get cached client info or register new client
        # @param server_metadata [ServerMetadata] server metadata
        # @return [ClientInfo] client information
        def get_or_register_client(server_metadata)
          # Check cache first
          client_info = storage.get_client_info(server_url)
          return client_info if client_info && !client_info.client_secret_expired?

          # Register new client if no cached info or secret expired
          if server_metadata.supports_registration?
            register_client(server_metadata)
          else
            raise Errors::TransportError.new(
              "OAuth server does not support dynamic client registration", nil, nil
            )
          end
        end

        # Register OAuth client dynamically (RFC 7591)
        # @param server_metadata [ServerMetadata] server metadata
        # @return [ClientInfo] registered client info
        def register_client(server_metadata)
          logger.debug("Registering OAuth client at: #{server_metadata.registration_endpoint}")

          metadata = build_client_metadata
          response = post_client_registration(server_metadata, metadata)
          data = parse_registration_response(response)

          registered_metadata = parse_registered_metadata(data)
          warn_redirect_uri_mismatch(registered_metadata)

          client_info = create_client_info_from_response(data, registered_metadata)
          storage.set_client_info(server_url, client_info)
          logger.debug("Client registered successfully: #{client_info.client_id}")
          client_info
        end

        def build_client_metadata
          ClientMetadata.new(
            redirect_uris: [redirect_uri],
            token_endpoint_auth_method: "none",
            grant_types: %w[authorization_code refresh_token],
            response_types: ["code"],
            scope: scope
          )
        end

        def post_client_registration(server_metadata, metadata)
          @http_client.post(
            server_metadata.registration_endpoint,
            headers: { "Content-Type" => "application/json" },
            json: metadata.to_h
          )
        end

        def parse_registration_response(response)
          unless [201, 200].include?(response.status)
            raise Errors::TransportError.new("Client registration failed: HTTP #{response.status}", nil, nil)
          end

          JSON.parse(response.body.to_s)
        end

        def parse_registered_metadata(data)
          ClientMetadata.new(
            redirect_uris: data["redirect_uris"] || [redirect_uri],
            token_endpoint_auth_method: data["token_endpoint_auth_method"] || "none",
            grant_types: data["grant_types"] || %w[authorization_code refresh_token],
            response_types: data["response_types"] || ["code"],
            scope: data["scope"]
          )
        end

        def warn_redirect_uri_mismatch(registered_metadata)
          return if registered_metadata.redirect_uris.first == redirect_uri

          logger.warn("OAuth server changed redirect_uri:")
          logger.warn("  Requested:  #{redirect_uri}")
          logger.warn("  Registered: #{registered_metadata.redirect_uris.first}")
        end

        def create_client_info_from_response(data, registered_metadata)
          ClientInfo.new(
            client_id: data["client_id"],
            client_secret: data["client_secret"],
            client_id_issued_at: data["client_id_issued_at"],
            client_secret_expires_at: data["client_secret_expires_at"],
            metadata: registered_metadata
          )
        end

        # Build OAuth authorization URL
        # @param server_metadata [ServerMetadata] server metadata
        # @param client_info [ClientInfo] client info
        # @param pkce [PKCE] PKCE parameters
        # @param state [String] CSRF state
        # @return [String] authorization URL
        def build_authorization_url(server_metadata, client_info, pkce, state)
          # Use registered redirect_uri (may differ from requested)
          registered_redirect_uri = client_info.metadata.redirect_uris.first

          params = {
            response_type: "code",
            client_id: client_info.client_id,
            redirect_uri: registered_redirect_uri,
            scope: scope,
            state: state, # CSRF protection
            code_challenge: pkce.code_challenge,
            code_challenge_method: pkce.code_challenge_method, # S256
            resource: server_url # RFC 8707 - Resource Indicators
          }.compact

          uri = URI.parse(server_metadata.authorization_endpoint)
          uri.query = URI.encode_www_form(params)
          uri.to_s
        end

        # Exchange authorization code for access token
        # @param server_metadata [ServerMetadata] server metadata
        # @param client_info [ClientInfo] client info
        # @param code [String] authorization code
        # @param pkce [PKCE] PKCE parameters
        # @return [Token] access token
        def exchange_authorization_code(server_metadata, client_info, code, pkce)
          logger.debug("Exchanging authorization code for access token")

          registered_redirect_uri = client_info.metadata.redirect_uris.first
          params = build_token_exchange_params(client_info, code, pkce, registered_redirect_uri)

          response = post_token_exchange(server_metadata, params)
          response = retry_token_exchange_if_redirect_mismatch(
            response, server_metadata, params, registered_redirect_uri
          )

          validate_token_response!(response)
          parse_token_response(response)
        end

        def build_token_exchange_params(client_info, code, pkce, registered_redirect_uri)
          params = {
            grant_type: "authorization_code",
            code: code,
            redirect_uri: registered_redirect_uri,
            client_id: client_info.client_id,
            code_verifier: pkce.code_verifier,
            resource: server_url
          }

          add_client_secret_if_needed(params, client_info)
          params
        end

        def add_client_secret_if_needed(params, client_info)
          return unless client_info.client_secret
          return unless client_info.metadata.token_endpoint_auth_method == "client_secret_post"

          params[:client_secret] = client_info.client_secret
        end

        def post_token_exchange(server_metadata, params)
          @http_client.post(
            server_metadata.token_endpoint,
            headers: { "Content-Type" => "application/x-www-form-urlencoded" },
            form: params
          )
        end

        def retry_token_exchange_if_redirect_mismatch(response, server_metadata, params, registered_redirect_uri)
          return response if response.status == 200

          redirect_hint = extract_redirect_mismatch(response.body.to_s)
          return response unless redirect_hint
          return response if redirect_hint[:expected] == registered_redirect_uri

          logger.warn("Redirect URI mismatch, retrying with: #{redirect_hint[:expected]}")
          params[:redirect_uri] = redirect_hint[:expected]
          post_token_exchange(server_metadata, params)
        end

        def validate_token_response!(response)
          return if response.status == 200

          raise Errors::TransportError.new("Token exchange failed: HTTP #{response.status}", nil, nil)
        end

        def parse_token_response(response)
          data = JSON.parse(response.body.to_s)
          Token.new(
            access_token: data["access_token"],
            token_type: data["token_type"] || "Bearer",
            expires_in: data["expires_in"],
            scope: data["scope"],
            refresh_token: data["refresh_token"]
          )
        end

        # Refresh access token using refresh token
        # @param token [Token] current token with refresh_token
        # @return [Token, nil] new token or nil if refresh failed
        def refresh_token(token)
          return nil unless token.refresh_token

          logger.debug("Refreshing access token")

          server_metadata = discover_authorization_server
          client_info = storage.get_client_info(server_url)
          return nil unless server_metadata && client_info

          execute_token_refresh(server_metadata, client_info, token)
        rescue JSON::ParserError => e
          logger.warn("Invalid token refresh response: #{e.message}")
          nil
        rescue HTTPX::Error => e
          logger.warn("Network error during token refresh: #{e.message}")
          nil
        end

        def execute_token_refresh(server_metadata, client_info, token)
          params = build_refresh_params(client_info, token)
          response = post_token_refresh(server_metadata, params)

          return nil unless response.status == 200

          new_token = parse_refresh_response(response, token)
          storage.set_token(server_url, new_token)
          logger.debug("Token refreshed successfully")
          new_token
        end

        def build_refresh_params(client_info, token)
          params = {
            grant_type: "refresh_token",
            refresh_token: token.refresh_token,
            client_id: client_info.client_id,
            resource: server_url
          }

          add_client_secret_if_needed(params, client_info)
          params
        end

        def post_token_refresh(server_metadata, params)
          response = @http_client.post(
            server_metadata.token_endpoint,
            headers: { "Content-Type" => "application/x-www-form-urlencoded" },
            form: params
          )

          logger.warn("Token refresh failed: HTTP #{response.status}") unless response.status == 200
          response
        end

        def parse_refresh_response(response, old_token)
          data = JSON.parse(response.body.to_s)
          Token.new(
            access_token: data["access_token"],
            token_type: data["token_type"] || "Bearer",
            expires_in: data["expires_in"],
            scope: data["scope"],
            refresh_token: data["refresh_token"] || old_token.refresh_token
          )
        end

        # Extract redirect URI mismatch details from error response
        # @param body [String] error response body
        # @return [Hash, nil] mismatch details or nil
        def extract_redirect_mismatch(body)
          data = JSON.parse(body)
          error = data["error"] || data[:error]
          return nil unless error == "unauthorized_client"

          description = data["error_description"] || data[:error_description]
          return nil unless description.is_a?(String)

          # Parse common OAuth error message format
          match = description.match(%r{You sent\s+(https?://\S+)[,.]?\s+and we expected\s+(https?://\S+)}i)
          return nil unless match

          {
            sent: match[1],
            expected: match[2],
            description: description
          }
        rescue JSON::ParserError
          nil
        end

        # In-memory storage for OAuth data
        class MemoryStorage
          def initialize
            @tokens = {}
            @client_infos = {}
            @server_metadata = {}
            @pkce_data = {}
            @state_data = {}
          end

          # Token storage
          def get_token(server_url)
            @tokens[server_url]
          end

          def set_token(server_url, token)
            @tokens[server_url] = token
          end

          # Client registration storage
          def get_client_info(server_url)
            @client_infos[server_url]
          end

          def set_client_info(server_url, client_info)
            @client_infos[server_url] = client_info
          end

          # Server metadata caching
          def get_server_metadata(server_url)
            @server_metadata[server_url]
          end

          def set_server_metadata(server_url, metadata)
            @server_metadata[server_url] = metadata
          end

          # PKCE state management (temporary)
          def get_pkce(server_url)
            @pkce_data[server_url]
          end

          def set_pkce(server_url, pkce)
            @pkce_data[server_url] = pkce
          end

          def delete_pkce(server_url)
            @pkce_data.delete(server_url)
          end

          # State parameter management (temporary)
          def get_state(server_url)
            @state_data[server_url]
          end

          def set_state(server_url, state)
            @state_data[server_url] = state
          end

          def delete_state(server_url)
            @state_data.delete(server_url)
          end
        end
      end
    end
  end
end
