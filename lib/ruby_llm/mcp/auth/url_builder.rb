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
          build_discovery_urls(server_url, discovery_type).first
        end

        # Build ordered discovery URLs for OAuth metadata
        # @param server_url [String] MCP server URL
        # @param discovery_type [Symbol] :authorization_server or :protected_resource
        # @return [Array<String>] discovery URLs in priority order
        def self.build_discovery_urls(server_url, discovery_type = :authorization_server)
          case discovery_type
          when :authorization_server
            build_authorization_server_metadata_urls(server_url)
          when :protected_resource
            build_protected_resource_metadata_urls(server_url)
          else
            raise ArgumentError, "Unknown discovery type: #{discovery_type}"
          end
        end

        # Build protected resource metadata URLs (RFC 9728 / MCP Section 4.2)
        # Ordered as required by the MCP spec:
        # 1) Path-based well-known URI
        # 2) Root well-known URI
        # @param server_url [String] MCP server URL
        # @return [Array<String>] protected resource metadata URLs in priority order
        def self.build_protected_resource_metadata_urls(server_url)
          uri = URI.parse(server_url)
          origin = origin_for(uri)
          endpoint = "oauth-protected-resource"
          path_component = normalized_path_component(uri.path)

          urls = []
          urls << "#{origin}/.well-known/#{endpoint}/#{path_component}" if path_component
          urls << "#{origin}/.well-known/#{endpoint}"
          urls.uniq
        end

        # Build authorization server metadata URLs (RFC 8414 + OIDC compatibility)
        # @param issuer_url [String] authorization server issuer URL
        # @return [Array<String>] metadata URLs in required priority order
        def self.build_authorization_server_metadata_urls(issuer_url)
          uri = URI.parse(issuer_url)
          origin = origin_for(uri)
          path_component = normalized_path_component(uri.path)

          if path_component
            [
              "#{origin}/.well-known/oauth-authorization-server/#{path_component}",
              "#{origin}/.well-known/openid-configuration/#{path_component}",
              "#{origin}/#{path_component}/.well-known/openid-configuration"
            ]
          else
            [
              "#{origin}/.well-known/oauth-authorization-server",
              "#{origin}/.well-known/openid-configuration"
            ]
          end
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
          origin_for(uri)
        end

        # Check if port is default for scheme
        # @param uri [URI] parsed URI
        # @return [Boolean] true if default port
        def self.default_port?(uri)
          (uri.scheme == "http" && uri.port == 80) ||
            (uri.scheme == "https" && uri.port == 443)
        end

        # Build scheme://host(:port)
        # @param uri [URI] parsed URI
        # @return [String] origin URL
        def self.origin_for(uri)
          origin = "#{uri.scheme}://#{uri.host}"
          origin += ":#{uri.port}" if uri.port && !default_port?(uri)
          origin
        end

        # Convert URI path to a clean path component with no leading/trailing slash
        # @param path [String, nil] path from URI
        # @return [String, nil] normalized path component or nil for root
        def self.normalized_path_component(path)
          return nil if path.nil? || path.empty? || path == "/"

          cleaned = path.split("/").reject(&:empty?).join("/")
          cleaned.empty? ? nil : cleaned
        end
      end
    end
  end
end
