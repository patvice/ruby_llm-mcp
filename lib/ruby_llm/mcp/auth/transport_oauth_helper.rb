# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      # Helper module for preparing OAuth providers for transports
      # This keeps OAuth logic out of the Native module while making it reusable
      module TransportOauthHelper
        module_function

        # Check if OAuth configuration is present
        # @param config [Hash] transport configuration hash
        # @return [Boolean] true if OAuth config is present
        def oauth_config_present?(config)
          oauth_config = config[:oauth] || config["oauth"]
          return false if oauth_config.nil?

          # If it's an OAuth provider instance, it's present
          return true if oauth_config.respond_to?(:access_token)

          # If it's a hash, check if it's not empty
          !oauth_config.empty?
        end

        # Create OAuth provider from configuration
        # Accepts either a provider instance or a configuration hash
        # @param config [Hash] transport configuration hash (will be modified)
        # @return [OAuthProvider, BrowserOAuthProvider, nil] OAuth provider or nil
        def create_oauth_provider(config)
          oauth_config = config.delete(:oauth) || config.delete("oauth")
          return nil unless oauth_config

          # If provider key exists with an instance, use it
          if oauth_config.is_a?(Hash) && (oauth_config[:provider] || oauth_config["provider"])
            return oauth_config[:provider] || oauth_config["provider"]
          end

          # If oauth_config itself is a provider instance, use it directly
          if oauth_config.respond_to?(:access_token) && oauth_config.respond_to?(:start_authorization_flow)
            return oauth_config
          end

          # Otherwise create new provider from config hash
          server_url = determine_server_url(config)
          return nil unless server_url

          redirect_uri = oauth_config[:redirect_uri] || oauth_config["redirect_uri"] || "http://localhost:8080/callback"
          scope = oauth_config[:scope] || oauth_config["scope"]
          storage = oauth_config[:storage] || oauth_config["storage"]
          grant_type = oauth_config[:grant_type] || oauth_config["grant_type"] || :authorization_code

          RubyLLM::MCP::Auth::OAuthProvider.new(
            server_url: server_url,
            redirect_uri: redirect_uri,
            scope: scope,
            logger: MCP.logger,
            storage: storage,
            grant_type: grant_type
          )
        end

        # Determine server URL from transport config
        # @param config [Hash] transport configuration hash
        # @return [String, nil] server URL or nil
        def determine_server_url(config)
          config[:url] || config["url"]
        end

        # Prepare HTTP transport configuration with OAuth provider
        # @param config [Hash] transport configuration hash (will be modified)
        # @param oauth_provider [OAuthProvider, nil] OAuth provider instance
        # @return [Hash] prepared configuration
        def prepare_http_transport_config(config, oauth_provider)
          options = {
            version: config.delete(:version) || config.delete("version"),
            headers: config.delete(:headers) || config.delete("headers"),
            oauth_provider: oauth_provider,
            reconnection: config.delete(:reconnection) || config.delete("reconnection"),
            reconnection_options: config.delete(:reconnection_options) || config.delete("reconnection_options"),
            rate_limit: config.delete(:rate_limit) || config.delete("rate_limit"),
            session_id: config.delete(:session_id) || config.delete("session_id")
          }.compact

          config[:options] = options
          config
        end

        # Prepare stdio transport configuration
        # @param config [Hash] transport configuration hash (will be modified)
        # @return [Hash] prepared configuration
        def prepare_stdio_transport_config(config)
          # Remove OAuth config from stdio transport (not supported)
          config.delete(:oauth)
          config.delete("oauth")

          options = {
            args: config.delete(:args) || config.delete("args"),
            env: config.delete(:env) || config.delete("env")
          }.compact

          config[:options] = options unless options.empty?
          config
        end
      end
    end
  end
end
