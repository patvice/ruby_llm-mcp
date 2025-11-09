# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      # In-memory storage for OAuth data
      # Stores tokens, client registrations, server metadata, and temporary session data
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
