# frozen_string_literal: true

require "base64"
require "digest/sha2"
require "securerandom"
require "time"

module RubyLLM
  module MCP
    module Auth
      # OAuth configuration constants
      # Token refresh buffer time in seconds (5 minutes)
      TOKEN_REFRESH_BUFFER = 300

      # Default OAuth timeout in seconds (30 seconds)
      DEFAULT_OAUTH_TIMEOUT = 30

      # CSRF state parameter size in bytes (32 bytes)
      CSRF_STATE_SIZE = 32

      # PKCE code verifier size in bytes (32 bytes)
      PKCE_VERIFIER_SIZE = 32

      # Represents an OAuth 2.1 access token with expiration tracking
      class Token
        attr_reader :access_token, :token_type, :expires_in, :scope, :refresh_token, :expires_at

        def initialize(access_token:, token_type: "Bearer", expires_in: nil, scope: nil, refresh_token: nil)
          @access_token = access_token
          @token_type = token_type
          @expires_in = expires_in
          @scope = scope
          @refresh_token = refresh_token
          @expires_at = expires_in ? Time.now + expires_in : nil
        end

        # Check if token has expired
        # @return [Boolean] true if token is expired
        def expired?
          return false unless @expires_at

          Time.now >= @expires_at
        end

        # Check if token expires soon (within configured buffer)
        # This enables proactive token refresh
        # @return [Boolean] true if token expires within the buffer period
        def expires_soon?
          return false unless @expires_at

          Time.now >= (@expires_at - TOKEN_REFRESH_BUFFER)
        end

        # Format token for Authorization header
        # @return [String] formatted as "Bearer {access_token}"
        def to_header
          "#{@token_type} #{@access_token}"
        end

        # Serialize token to hash
        # @return [Hash] token data
        def to_h
          {
            access_token: @access_token,
            token_type: @token_type,
            expires_in: @expires_in,
            scope: @scope,
            refresh_token: @refresh_token,
            expires_at: @expires_at&.iso8601
          }
        end

        # Deserialize token from hash
        # @param data [Hash] token data
        # @return [Token] new token instance
        def self.from_h(data)
          token = new(
            access_token: data[:access_token] || data["access_token"],
            token_type: data[:token_type] || data["token_type"] || "Bearer",
            expires_in: data[:expires_in] || data["expires_in"],
            scope: data[:scope] || data["scope"],
            refresh_token: data[:refresh_token] || data["refresh_token"]
          )

          # Restore expires_at if present
          expires_at_str = data[:expires_at] || data["expires_at"]
          if expires_at_str
            token.instance_variable_set(:@expires_at, Time.parse(expires_at_str))
          end

          token
        end
      end

      # Client metadata for dynamic client registration (RFC 7591)
      # Supports all optional parameters from the specification
      class ClientMetadata
        attr_reader :redirect_uris, :token_endpoint_auth_method, :grant_types, :response_types, :scope,
                    :client_name, :client_uri, :logo_uri, :contacts, :tos_uri, :policy_uri,
                    :jwks_uri, :jwks, :software_id, :software_version

        def initialize( # rubocop:disable Metrics/ParameterLists
          redirect_uris:,
          token_endpoint_auth_method: "none",
          grant_types: %w[authorization_code refresh_token],
          response_types: ["code"],
          scope: nil,
          client_name: nil,
          client_uri: nil,
          logo_uri: nil,
          contacts: nil,
          tos_uri: nil,
          policy_uri: nil,
          jwks_uri: nil,
          jwks: nil,
          software_id: nil,
          software_version: nil
        )
          @redirect_uris = redirect_uris
          @token_endpoint_auth_method = token_endpoint_auth_method
          @grant_types = grant_types
          @response_types = response_types
          @scope = scope
          @client_name = client_name
          @client_uri = client_uri
          @logo_uri = logo_uri
          @contacts = contacts
          @tos_uri = tos_uri
          @policy_uri = policy_uri
          @jwks_uri = jwks_uri
          @jwks = jwks
          @software_id = software_id
          @software_version = software_version
        end

        # Convert to hash for registration request
        # @return [Hash] client metadata
        def to_h
          {
            redirect_uris: @redirect_uris,
            token_endpoint_auth_method: @token_endpoint_auth_method,
            grant_types: @grant_types,
            response_types: @response_types,
            scope: @scope,
            client_name: @client_name,
            client_uri: @client_uri,
            logo_uri: @logo_uri,
            contacts: @contacts,
            tos_uri: @tos_uri,
            policy_uri: @policy_uri,
            jwks_uri: @jwks_uri,
            jwks: @jwks,
            software_id: @software_id,
            software_version: @software_version
          }.compact
        end
      end

      # Registered client information from authorization server
      class ClientInfo
        attr_reader :client_id, :client_secret, :client_id_issued_at, :client_secret_expires_at, :metadata

        def initialize(client_id:, client_secret: nil, client_id_issued_at: nil, client_secret_expires_at: nil,
                       metadata: nil)
          @client_id = client_id
          @client_secret = client_secret
          @client_id_issued_at = client_id_issued_at
          @client_secret_expires_at = client_secret_expires_at
          @metadata = metadata
        end

        # Check if client secret has expired
        # @return [Boolean] true if client secret is expired
        def client_secret_expired?
          return false unless @client_secret_expires_at

          Time.now.to_i >= @client_secret_expires_at
        end

        # Serialize to hash
        # @return [Hash] client info
        def to_h
          {
            client_id: @client_id,
            client_secret: @client_secret,
            client_id_issued_at: @client_id_issued_at,
            client_secret_expires_at: @client_secret_expires_at,
            metadata: @metadata&.to_h
          }
        end

        # Deserialize from hash
        # @param data [Hash] client info data
        # @return [ClientInfo] new instance
        def self.from_h(data)
          metadata_data = data[:metadata] || data["metadata"]
          metadata = if metadata_data
                       ClientMetadata.new(**metadata_data.transform_keys(&:to_sym))
                     end

          new(
            client_id: data[:client_id] || data["client_id"],
            client_secret: data[:client_secret] || data["client_secret"],
            client_id_issued_at: data[:client_id_issued_at] || data["client_id_issued_at"],
            client_secret_expires_at: data[:client_secret_expires_at] || data["client_secret_expires_at"],
            metadata: metadata
          )
        end
      end

      # OAuth Authorization Server Metadata (RFC 8414)
      class ServerMetadata
        attr_reader :issuer, :authorization_endpoint, :token_endpoint, :registration_endpoint,
                    :scopes_supported, :response_types_supported, :grant_types_supported

        def initialize(issuer:, authorization_endpoint:, token_endpoint:, options: {})
          @issuer = issuer
          @authorization_endpoint = authorization_endpoint
          @token_endpoint = token_endpoint
          @registration_endpoint = options[:registration_endpoint] || options["registration_endpoint"]
          @scopes_supported = options[:scopes_supported] || options["scopes_supported"]
          @response_types_supported = options[:response_types_supported] || options["response_types_supported"]
          @grant_types_supported = options[:grant_types_supported] || options["grant_types_supported"]
        end

        # Check if dynamic client registration is supported
        # @return [Boolean] true if registration endpoint exists
        def supports_registration?
          !@registration_endpoint.nil?
        end

        # Serialize to hash
        # @return [Hash] server metadata
        def to_h
          {
            issuer: @issuer,
            authorization_endpoint: @authorization_endpoint,
            token_endpoint: @token_endpoint,
            registration_endpoint: @registration_endpoint,
            scopes_supported: @scopes_supported,
            response_types_supported: @response_types_supported,
            grant_types_supported: @grant_types_supported
          }.compact
        end

        # Deserialize from hash
        # @param data [Hash] server metadata
        # @return [ServerMetadata] new instance
        def self.from_h(data)
          new(
            issuer: data[:issuer] || data["issuer"],
            authorization_endpoint: data[:authorization_endpoint] || data["authorization_endpoint"],
            token_endpoint: data[:token_endpoint] || data["token_endpoint"],
            registration_endpoint: data[:registration_endpoint] || data["registration_endpoint"],
            scopes_supported: data[:scopes_supported] || data["scopes_supported"],
            response_types_supported: data[:response_types_supported] || data["response_types_supported"],
            grant_types_supported: data[:grant_types_supported] || data["grant_types_supported"]
          )
        end
      end

      # OAuth Protected Resource Metadata (RFC 9728)
      # Used for authorization server delegation
      class ResourceMetadata
        attr_reader :resource, :authorization_servers

        def initialize(resource:, authorization_servers:)
          @resource = resource
          @authorization_servers = authorization_servers
        end

        # Serialize to hash
        # @return [Hash] resource metadata
        def to_h
          {
            resource: @resource,
            authorization_servers: @authorization_servers
          }
        end

        # Deserialize from hash
        # @param data [Hash] resource metadata
        # @return [ResourceMetadata] new instance
        def self.from_h(data)
          new(
            resource: data[:resource] || data["resource"],
            authorization_servers: data[:authorization_servers] || data["authorization_servers"]
          )
        end
      end

      # Proof Key for Code Exchange (PKCE) implementation (RFC 7636)
      # Required for OAuth 2.1 security
      class PKCE
        attr_reader :code_verifier, :code_challenge, :code_challenge_method

        def initialize
          @code_verifier = generate_code_verifier
          @code_challenge = generate_code_challenge(@code_verifier)
          @code_challenge_method = "S256" # SHA256 - only secure method for OAuth 2.1
        end

        # Serialize to hash
        # @return [Hash] PKCE parameters
        def to_h
          {
            code_verifier: @code_verifier,
            code_challenge: @code_challenge,
            code_challenge_method: @code_challenge_method
          }
        end

        # Deserialize from hash
        # @param data [Hash] PKCE data
        # @return [PKCE] new instance
        def self.from_h(data)
          pkce = allocate
          pkce.instance_variable_set(:@code_verifier, data[:code_verifier] || data["code_verifier"])
          pkce.instance_variable_set(:@code_challenge, data[:code_challenge] || data["code_challenge"])
          pkce.instance_variable_set(:@code_challenge_method,
                                     data[:code_challenge_method] || data["code_challenge_method"] || "S256")
          pkce
        end

        private

        # Generate cryptographically secure code verifier
        # @return [String] base64url-encoded random bytes
        def generate_code_verifier
          Base64.urlsafe_encode64(SecureRandom.random_bytes(PKCE_VERIFIER_SIZE), padding: false)
        end

        # Generate code challenge from verifier using SHA256
        # @param verifier [String] code verifier
        # @return [String] base64url-encoded SHA256 hash
        def generate_code_challenge(verifier)
          digest = Digest::SHA256.digest(verifier)
          Base64.urlsafe_encode64(digest, padding: false)
        end
      end
    end
  end
end
