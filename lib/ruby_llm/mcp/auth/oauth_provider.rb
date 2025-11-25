# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      # Core OAuth 2.1 provider implementing complete authorization flow
      # Supports RFC 7636 (PKCE), RFC 7591 (Dynamic Registration),
      # RFC 8414 (Server Metadata), RFC 8707 (Resource Indicators), RFC 9728 (Protected Resource Metadata)
      #
      # @note This class is not thread-safe. Each thread should use its own instance.
      class OAuthProvider
        attr_reader :server_url
        attr_accessor :redirect_uri, :scope, :logger, :storage, :grant_type

        # Normalize server URL for consistent comparison
        # @param url [String] raw URL
        # @return [String] normalized URL
        def self.normalize_url(url)
          uri = URI.parse(url)

          uri.scheme = uri.scheme&.downcase
          uri.host = uri.host&.downcase

          if (uri.scheme == "http" && uri.port == 80) || (uri.scheme == "https" && uri.port == 443)
            uri.port = nil
          end

          if uri.path.nil? || uri.path.empty? || uri.path == "/"
            uri.path = ""
          elsif uri.path.end_with?("/")
            uri.path = uri.path.chomp("/")
          end

          uri.fragment = nil
          uri.to_s
        end

        def initialize(server_url:, redirect_uri: "http://localhost:8080/callback", scope: nil, logger: nil, # rubocop:disable Metrics/ParameterLists
                       storage: nil, grant_type: :authorization_code)
          self.server_url = server_url
          self.redirect_uri = redirect_uri
          self.scope = scope
          self.logger = logger || MCP.logger
          self.storage = storage || MemoryStorage.new
          self.grant_type = grant_type.to_sym
          validate_redirect_uri!(redirect_uri)

          # Initialize HTTP client
          @http_client = create_http_client

          # Initialize service objects
          @discoverer = Discoverer.new(@http_client, self.storage, self.logger)
          @client_registrar = ClientRegistrar.new(@http_client, self.storage, self.logger, MCP.config)
          @token_manager = TokenManager.new(@http_client, self.logger)
          @session_manager = SessionManager.new(self.storage)

          # Initialize flow orchestrators
          @auth_code_flow = Flows::AuthorizationCodeFlow.new(
            discoverer: @discoverer,
            client_registrar: @client_registrar,
            session_manager: @session_manager,
            token_manager: @token_manager,
            storage: self.storage,
            logger: self.logger
          )
          @client_creds_flow = Flows::ClientCredentialsFlow.new(
            discoverer: @discoverer,
            client_registrar: @client_registrar,
            token_manager: @token_manager,
            storage: self.storage,
            logger: self.logger
          )
        end

        # Get current access token, refreshing if needed
        # @return [Token, nil] valid access token or nil
        def access_token
          logger.debug("OAuth access_token: Looking up token for server_url='#{server_url}'")
          token = storage.get_token(server_url)
          logger.debug("OAuth access_token: Storage returned token=#{token ? 'present' : 'nil'}")

          if token
            logger.debug("  Token expires_at: #{token.expires_at}")
            logger.debug("  Token expired?: #{token.expired?}")
            logger.debug("  Token expires_soon?: #{token.expires_soon?}")
          else
            logger.warn("✗ No token found in storage for server_url='#{server_url}'")
            logger.warn("  Check that authentication completed and stored the token")
            return nil
          end

          # Return token if still valid
          return token unless token.expired? || token.expires_soon?

          # Try to refresh if we have a refresh token
          logger.debug("Token expired or expiring soon, attempting refresh...")
          refresh_token(token) if token.refresh_token
        end

        # Authenticate and return current access token
        # This is a convenience method for consistency with BrowserOAuthProvider
        # For standard OAuth flow, external authorization is required before calling this
        # @return [Token] current valid access token
        # @raise [Errors::TransportError] if not authenticated or token unavailable
        def authenticate
          token = access_token
          unless token
            raise Errors::TransportError.new(
              message: "Not authenticated. Please complete OAuth authorization flow first. " \
                       "For standard OAuth, you must authorize externally and exchange the code."
            )
          end
          token
        end

        # Start OAuth authorization flow (authorization code grant)
        # @return [String] authorization URL for user to visit
        def start_authorization_flow
          @auth_code_flow.start(
            server_url,
            redirect_uri,
            scope,
            https_validator: method(:validate_https_endpoint)
          )
        end

        # Perform client credentials flow (application authentication without user)
        # @param scope [String] optional scope override
        # @return [Token] access token
        def client_credentials_flow(scope: nil)
          @client_creds_flow.execute(server_url, redirect_uri, scope || self.scope)
        end

        # Complete OAuth authorization flow after callback
        # @param code [String] authorization code from callback
        # @param state [String] state parameter from callback
        # @return [Token] access token
        def complete_authorization_flow(code, state)
          @auth_code_flow.complete(server_url, code, state)
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

        # Handle authentication challenge from server (401 response)
        # Attempts to refresh token or raises error if interactive auth required
        # @param www_authenticate [String, nil] WWW-Authenticate header value
        # @param resource_metadata_url [String, nil] Resource metadata URL from response
        # @param requested_scope [String, nil] Scope from WWW-Authenticate challenge
        # @return [Boolean] true if authentication was refreshed successfully
        # @raise [Errors::AuthenticationRequiredError] if interactive auth is required
        def handle_authentication_challenge(www_authenticate: nil, resource_metadata_url: nil, requested_scope: nil)
          logger.debug("Handling authentication challenge")
          logger.debug("  WWW-Authenticate: #{www_authenticate}") if www_authenticate
          logger.debug("  Resource metadata URL: #{resource_metadata_url}") if resource_metadata_url
          logger.debug("  Requested scope: #{requested_scope}") if requested_scope

          # Parse WWW-Authenticate header if provided
          final_requested_scope = requested_scope
          if www_authenticate
            challenge_info = parse_www_authenticate(www_authenticate)
            final_requested_scope ||= challenge_info[:scope]
            # NOTE: resource_metadata_url from challenge_info could be used for future discovery
          end

          # Update scope if server requested different scope
          if final_requested_scope && final_requested_scope != scope
            logger.debug("Updating scope from '#{scope}' to '#{final_requested_scope}'")
            self.scope = final_requested_scope
          end

          # Try to refresh existing token
          token = storage.get_token(server_url)
          if token&.refresh_token
            logger.debug("Attempting token refresh with existing refresh token")
            refreshed_token = refresh_token(token)
            return true if refreshed_token
          end

          # If we have client credentials, try that flow
          if grant_type == :client_credentials
            logger.debug("Attempting client credentials flow")
            begin
              new_token = client_credentials_flow(scope: requested_scope)
              return true if new_token
            rescue StandardError => e
              logger.warn("Client credentials flow failed: #{e.message}")
            end
          end

          # Cannot automatically authenticate - interactive auth required
          logger.warn("Cannot automatically authenticate - interactive authorization required")
          raise Errors::AuthenticationRequiredError.new(
            message: "OAuth authentication required. Token refresh failed and interactive authorization is needed."
          )
        end

        # Parse WWW-Authenticate header to extract challenge parameters
        # @param header [String] WWW-Authenticate header value
        # @return [Hash] parsed challenge information
        def parse_www_authenticate(header)
          result = {}

          # Example: Bearer realm="example", scope="mcp:read mcp:write", resource_metadata_url="https://..."
          if header =~ /Bearer\s+(.+)/i
            params = ::Regexp.last_match(1)

            # Extract scope
            if params =~ /scope="([^"]+)"/
              result[:scope] = ::Regexp.last_match(1)
            end

            # Extract resource metadata URL
            if params =~ /resource_metadata_url="([^"]+)"/
              result[:resource_metadata_url] = ::Regexp.last_match(1)
            end

            # Extract realm
            if params =~ /realm="([^"]+)"/
              result[:realm] = ::Regexp.last_match(1)
            end
          end

          result
        end

        private

        # Create HTTP client for OAuth requests
        # @return [HTTPX::Session] HTTP client
        def create_http_client
          headers = {
            "Accept" => "application/json",
            "User-Agent" => "RubyLLM-MCP/#{RubyLLM::MCP::VERSION}"
          }
          headers["MCP-Protocol-Version"] = RubyLLM::MCP.config.protocol_version

          HTTPX.plugin(:follow_redirects).with(
            timeout: { total: DEFAULT_OAUTH_TIMEOUT },
            headers: headers
          )
        end

        # Normalize and set server URL
        # Ensures consistent URL format for storage keys
        def server_url=(url)
          @server_url = self.class.normalize_url(url)
        end

        # Validate redirect URI per OAuth 2.1 security requirements
        # @param uri [String] redirect URI
        # @raise [ArgumentError] if URI is invalid or not localhost/HTTPS
        def validate_redirect_uri!(uri)
          parsed = URI.parse(uri)
          is_localhost = ["localhost", "127.0.0.1", "::1"].include?(parsed.host)
          is_https = parsed.scheme == "https"

          unless is_localhost || is_https
            raise ArgumentError,
                  "Redirect URI must be localhost or HTTPS per OAuth 2.1 security requirements: #{uri}"
          end
        rescue URI::InvalidURIError => e
          raise ArgumentError, "Invalid redirect URI: #{uri} - #{e.message}"
        end

        # Validate HTTPS usage for OAuth endpoint (warning only)
        # @param url [String] endpoint URL
        # @param endpoint_name [String] descriptive name for logging
        def validate_https_endpoint(url, endpoint_name)
          uri = URI.parse(url)
          is_localhost = ["localhost", "127.0.0.1", "::1"].include?(uri.host)

          if uri.scheme != "https" && !is_localhost
            logger.warn("WARNING: #{endpoint_name} is not using HTTPS: #{url}")
            logger.warn("OAuth endpoints SHOULD use HTTPS in production environments")
          end
        end

        # Refresh access token using refresh token
        # @param token [Token] current token with refresh_token
        # @return [Token, nil] new token or nil if refresh failed
        def refresh_token(token)
          return nil unless token.refresh_token

          server_metadata = @discoverer.discover(server_url)
          client_info = storage.get_client_info(server_url)
          return nil unless server_metadata && client_info

          new_token = @token_manager.refresh_token(server_metadata, client_info, token, server_url)
          storage.set_token(server_url, new_token) if new_token
          logger.debug("Token refreshed successfully") if new_token
          new_token
        end
      end
    end
  end
end
