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
        # @param resource_metadata_url [String, nil] explicit resource metadata URL from WWW-Authenticate
        # @return [ServerMetadata, nil] server metadata or nil
        def discover(server_url, resource_metadata_url: nil)
          logger.debug("Discovering OAuth authorization server for #{server_url}")

          cached = storage.get_server_metadata(server_url)
          return cached if cached && resource_metadata_url.nil?

          # Prefer protected resource metadata discovery to follow MCP authorization rules,
          # then fall back to direct auth server metadata discovery for compatibility.
          server_metadata = try_protected_resource_discovery(server_url, resource_metadata_url: resource_metadata_url)
          server_metadata ||= try_authorization_server_discovery(server_url)
          server_metadata ||= try_legacy_authorization_server_discovery(server_url)
          server_metadata ||= cached
          server_metadata ||= create_default_metadata(server_url)

          # Cache and return
          storage.set_server_metadata(server_url, server_metadata) if server_metadata
          server_metadata
        end

        private

        # Try oauth-authorization-server discovery (server is own auth server)
        # @param server_url [String] MCP server URL
        # @return [ServerMetadata, nil] server metadata or nil
        def try_authorization_server_discovery(server_url)
          urls = UrlBuilder.build_discovery_urls(server_url, :authorization_server)
          fetch_first_server_metadata(
            urls,
            context: "oauth-authorization-server discovery",
            expected_issuer: server_url
          )
        end

        # Try legacy MCP direct auth server discovery (pre-2025-06)
        # by treating the MCP server origin as the OAuth issuer.
        # @param server_url [String] MCP server URL
        # @return [ServerMetadata, nil] server metadata or nil
        def try_legacy_authorization_server_discovery(server_url)
          base_url = UrlBuilder.get_authorization_base_url(server_url)
          return nil if base_url == server_url

          logger.debug("Trying legacy oauth-authorization-server discovery with base URL: #{base_url}")
          urls = UrlBuilder.build_discovery_urls(base_url, :authorization_server)
          fetch_first_server_metadata(
            urls,
            context: "legacy oauth-authorization-server discovery",
            expected_issuer: base_url,
            enforce_issuer_match: false
          )
        end

        # Try oauth-protected-resource discovery (delegation pattern)
        # @param server_url [String] MCP server URL
        # @param resource_metadata_url [String, nil] explicit resource metadata URL from WWW-Authenticate
        # @return [ServerMetadata, nil] server metadata or nil
        def try_protected_resource_discovery(server_url, resource_metadata_url: nil)
          urls = []
          urls << resource_metadata_url if resource_metadata_url
          urls.concat(UrlBuilder.build_discovery_urls(server_url, :protected_resource))
          urls.uniq.each do |discovery_url|
            logger.debug("Trying protected resource discovery: #{discovery_url}")
            begin
              resource_metadata = fetch_resource_metadata(discovery_url, expected_resource: server_url)
              storage.set_resource_metadata(server_url, resource_metadata)

              auth_server_urls = Array(resource_metadata.authorization_servers).compact
              if auth_server_urls.empty?
                logger.debug("No authorization_servers found in resource metadata from #{discovery_url}")
                next
              end

              auth_server_urls.each do |auth_server_url|
                logger.debug("Found delegated auth server: #{auth_server_url}")
                server_metadata = try_authorization_server_metadata_discovery(auth_server_url)
                return server_metadata if server_metadata
              end
            rescue StandardError => e
              logger.debug("oauth-protected-resource discovery failed for #{discovery_url}: #{e.message}")
            end
          end
          nil
        end

        # Try RFC 8414 / OIDC-compatible metadata endpoints for an authorization server URL.
        # @param auth_server_url [String] authorization server URL
        # @return [ServerMetadata, nil] first successful metadata response
        def try_authorization_server_metadata_discovery(auth_server_url)
          urls = UrlBuilder.build_authorization_server_metadata_urls(auth_server_url)
          fetch_first_server_metadata(
            urls,
            context: "authorization server metadata discovery",
            expected_issuer: auth_server_url
          )
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
        def fetch_server_metadata(url, expected_issuer:, enforce_issuer_match: true)
          logger.debug("Fetching server metadata from #{url}")
          response = http_client.get(url)

          data = HttpResponseHandler.handle_response(response, context: "Server metadata fetch")
          validate_server_metadata!(
            data,
            expected_issuer: expected_issuer,
            source_url: url,
            enforce_issuer_match: enforce_issuer_match
          )

          ServerMetadata.new(
            issuer: data["issuer"],
            authorization_endpoint: data["authorization_endpoint"],
            token_endpoint: data["token_endpoint"],
            options: {
              registration_endpoint: data["registration_endpoint"],
              scopes_supported: data["scopes_supported"],
              response_types_supported: data["response_types_supported"],
              grant_types_supported: data["grant_types_supported"],
              code_challenge_methods_supported: data["code_challenge_methods_supported"]
            }
          )
        end

        # Fetch OAuth protected resource metadata
        # @param url [String] discovery URL
        # @return [ResourceMetadata] resource metadata
        def fetch_resource_metadata(url, expected_resource:)
          logger.debug("Fetching resource metadata from #{url}")
          response = http_client.get(url)

          data = HttpResponseHandler.handle_response(response, context: "Resource metadata fetch")
          validate_resource_metadata!(data, expected_resource: expected_resource, source_url: url)

          ResourceMetadata.new(
            resource: data["resource"],
            authorization_servers: data["authorization_servers"]
          )
        end

        # Return first successful server metadata response from candidate URLs.
        # @param urls [Array<String>] discovery URLs in priority order
        # @param context [String] log context
        # @return [ServerMetadata, nil] first metadata result or nil
        def fetch_first_server_metadata(urls, context:, expected_issuer:, enforce_issuer_match: true)
          urls.each do |url|
            logger.debug("Trying #{context} URL: #{url}")
            return fetch_server_metadata(
              url,
              expected_issuer: expected_issuer,
              enforce_issuer_match: enforce_issuer_match
            )
          rescue StandardError => e
            logger.debug("#{context} failed for #{url}: #{e.message}")
          end
          nil
        end

        # Validate RFC 8414 issuer matching rules before metadata is trusted.
        # @param data [Hash] metadata response body
        # @param expected_issuer [String] issuer identifier used to build discovery URLs
        # @param source_url [String] discovery URL used for fetching metadata
        # @raise [Errors::TransportError] when issuer is missing or mismatched
        def validate_server_metadata!(data, expected_issuer:, source_url:, enforce_issuer_match: true)
          issuer = data["issuer"]
          unless issuer.is_a?(String) && !issuer.empty?
            raise Errors::TransportError.new(
              message: "Server metadata fetch failed: missing required issuer in response from #{source_url}"
            )
          end

          return if issuer_identifiers_match?(issuer, expected_issuer)
          return warn_legacy_issuer_mismatch(expected_issuer, issuer, source_url) unless enforce_issuer_match

          raise Errors::TransportError.new(
            message: "Server metadata fetch failed: issuer '#{issuer}' did not match expected issuer " \
                     "'#{expected_issuer}' for #{source_url}"
          )
        end

        # Legacy MCP compatibility can return metadata whose issuer differs from the
        # MCP server origin. Accept it with warning so endpoint metadata still works.
        # @param expected_issuer [String]
        # @param issuer [String]
        # @param source_url [String]
        # @return [nil]
        def warn_legacy_issuer_mismatch(expected_issuer, issuer, source_url)
          logger.info(
            "Legacy OAuth discovery issuer mismatch accepted: expected '#{expected_issuer}', got '#{issuer}' " \
            "from #{source_url}"
          )
          nil
        end

        # Validate RFC 9728 resource matching rules before metadata is trusted.
        # @param data [Hash] metadata response body
        # @param expected_resource [String] resource identifier used for discovery/request
        # @param source_url [String] discovery URL used for fetching metadata
        # @raise [Errors::TransportError] when resource is missing or mismatched
        def validate_resource_metadata!(data, expected_resource:, source_url:)
          resource = data["resource"]
          unless resource.is_a?(String) && !resource.empty?
            raise Errors::TransportError.new(
              message: "Resource metadata fetch failed: missing required resource in response from #{source_url}"
            )
          end

          return if resource_identifiers_match?(resource, expected_resource)

          raise Errors::TransportError.new(
            message: "Resource metadata fetch failed: resource '#{resource}' did not match expected resource " \
                     "'#{expected_resource}' for #{source_url}"
          )
        end

        # Compare issuer identifiers allowing only normalization-equivalent
        # differences (for example, trailing slash mismatches).
        # @param issuer [String]
        # @param expected_issuer [String]
        # @return [Boolean]
        def issuer_identifiers_match?(issuer, expected_issuer)
          return true if issuer == expected_issuer

          normalized_issuer = normalize_issuer_identifier(issuer)
          normalized_expected = normalize_issuer_identifier(expected_issuer)
          normalized_issuer && normalized_expected && normalized_issuer == normalized_expected
        end

        # Compare resource identifiers allowing the metadata "resource" to identify
        # an enclosing protected resource (same origin + path-prefix semantics).
        # @param resource [String]
        # @param expected_resource [String]
        # @return [Boolean]
        def resource_identifiers_match?(resource, expected_resource)
          return true if resource == expected_resource

          resource_uri = parse_uri(resource)
          expected_uri = parse_uri(expected_resource)
          return false unless resource_uri && expected_uri
          return false unless comparable_origin(resource_uri) == comparable_origin(expected_uri)
          return false unless safe_for_prefix_comparison?(resource_uri, expected_uri)

          resource_segments = path_segments(resource_uri.path)
          expected_segments = path_segments(expected_uri.path)
          return false if resource_segments.length > expected_segments.length

          resource_segments == expected_segments.first(resource_segments.length)
        end

        # Normalize issuer for robust comparison.
        # @param issuer [String]
        # @return [String, nil]
        def normalize_issuer_identifier(issuer)
          uri = parse_uri(issuer)
          return nil unless uri

          path = uri.path.to_s
          path = "/" if path.empty?
          path = path.gsub(%r{/+\z}, "")
          path = "/" if path.empty?

          normalized = comparable_origin(uri)
          return nil unless normalized

          normalized += path unless path == "/"
          normalized
        end

        # @param uri [URI]
        # @return [String, nil]
        def comparable_origin(uri)
          scheme = uri.scheme&.downcase
          host = uri.host&.downcase
          return nil unless scheme && host

          port = uri.port
          default_port = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)

          origin = "#{scheme}://#{host}"
          origin += ":#{port}" if port && !default_port
          origin
        end

        # @param uri [URI]
        # @param expected_uri [URI]
        # @return [Boolean]
        def safe_for_prefix_comparison?(uri, expected_uri)
          [uri, expected_uri].all? do |candidate|
            candidate.userinfo.nil? && candidate.query.nil? && candidate.fragment.nil?
          end
        end

        # @param path [String, nil]
        # @return [Array<String>]
        def path_segments(path)
          path.to_s.split("/").reject(&:empty?)
        end

        # @param value [String]
        # @return [URI, nil]
        def parse_uri(value)
          URI.parse(value)
        rescue URI::InvalidURIError
          nil
        end
      end
    end
  end
end
