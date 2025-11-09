# frozen_string_literal: true

require "securerandom"

module RubyLLM
  module MCP
    module Auth
      # Service for managing OAuth session state (PKCE and CSRF state)
      # Handles creation, validation, and cleanup of temporary session data
      class SessionManager
        attr_reader :storage

        def initialize(storage)
          @storage = storage
        end

        # Create a new OAuth session with PKCE and CSRF state
        # @param server_url [String] MCP server URL
        # @return [Hash] session data with :pkce and :state
        def create_session(server_url)
          pkce = PKCE.new
          state = SecureRandom.urlsafe_base64(CSRF_STATE_SIZE)

          storage.set_pkce(server_url, pkce)
          storage.set_state(server_url, state)

          { pkce: pkce, state: state }
        end

        # Validate state parameter and retrieve session data
        # @param server_url [String] MCP server URL
        # @param state [String] state parameter from callback
        # @return [Hash] session data with :pkce and :client_info
        # @raise [ArgumentError] if state is invalid
        def validate_and_retrieve_session(server_url, state)
          stored_state = storage.get_state(server_url)
          unless stored_state && Security.secure_compare(stored_state, state)
            raise ArgumentError, "Invalid state parameter"
          end

          {
            pkce: storage.get_pkce(server_url),
            client_info: storage.get_client_info(server_url)
          }
        end

        # Clean up temporary session data
        # @param server_url [String] MCP server URL
        def cleanup_session(server_url)
          storage.delete_pkce(server_url)
          storage.delete_state(server_url)
        end
      end
    end
  end
end
