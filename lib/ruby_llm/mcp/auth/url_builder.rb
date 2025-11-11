# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      # Utility class for building OAuth URLs
      # Handles discovery URLs, authorization URLs, and URL normalization
      class UrlBuilder
        # Build discovery URL for OAuth server metadata
        # @param server_url [String] MCP server URL
        # @param discovery_type [Symbol] :authorization_server or :protected_resource
        # @return [String] discovery URL
        def self.build_discovery_url(server_url, discovery_type = :authorization_server)
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

        # Build OAuth authorization URL
        # @param authorization_endpoint [String] auth server endpoint
        # @param client_id [String] client ID
        # @param redirect_uri [String] redirect URI
        # @param scope [String, nil] requested scope
        # @param state [String] CSRF state
        # @param pkce [PKCE] PKCE parameters
        # @param resource [String] resource indicator (RFC 8707)
        # @return [String] authorization URL
        def self.build_authorization_url(authorization_endpoint, client_id, redirect_uri, scope, state, pkce, resource) # rubocop:disable Metrics/ParameterLists
          params = {
            response_type: "code",
            client_id: client_id,
            redirect_uri: redirect_uri,
            scope: scope,
            state: state, # CSRF protection
            code_challenge: pkce.code_challenge,
            code_challenge_method: pkce.code_challenge_method, # S256
            resource: resource # RFC 8707 - Resource Indicators
          }.compact

          uri = URI.parse(authorization_endpoint)
          uri.query = URI.encode_www_form(params)
          uri.to_s
        end

        # Get authorization base URL from server URL
        # @param server_url [String] MCP server URL
        # @return [String] authorization base URL (scheme + host + port)
        def self.get_authorization_base_url(server_url)
          uri = URI.parse(server_url)
          origin = "#{uri.scheme}://#{uri.host}"
          origin += ":#{uri.port}" if uri.port && !default_port?(uri)
          origin
        end

        # Check if port is default for scheme
        # @param uri [URI] parsed URI
        # @return [Boolean] true if default port
        def self.default_port?(uri)
          (uri.scheme == "http" && uri.port == 80) ||
            (uri.scheme == "https" && uri.port == 443)
        end
      end
    end
  end
end
