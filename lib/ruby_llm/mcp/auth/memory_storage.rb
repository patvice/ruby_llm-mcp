# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      # In-memory storage for OAuth data
      # Stores tokens, client registrations, server metadata, and temporary session data
      class MemoryStorage
        def initialize
          @mutex = Mutex.new
          @tokens = {}
          @client_infos = {}
          @server_metadata = {}
          @pkce_data = {}
          @state_data = {}
          @resource_metadata = {}
        end

        # Token storage
        def get_token(server_url)
          @mutex.synchronize { @tokens[server_url] }
        end

        def set_token(server_url, token)
          @mutex.synchronize { @tokens[server_url] = token }
        end

        def delete_token(server_url)
          @mutex.synchronize { @tokens.delete(server_url) }
        end

        # Client registration storage
        def get_client_info(server_url)
          @mutex.synchronize { @client_infos[server_url] }
        end

        def set_client_info(server_url, client_info)
          @mutex.synchronize { @client_infos[server_url] = client_info }
        end

        # Server metadata caching
        def get_server_metadata(server_url)
          @mutex.synchronize { @server_metadata[server_url] }
        end

        def set_server_metadata(server_url, metadata)
          @mutex.synchronize { @server_metadata[server_url] = metadata }
        end

        # PKCE state management (temporary)
        def get_pkce(server_url)
          @mutex.synchronize { @pkce_data[server_url] }
        end

        def set_pkce(server_url, pkce)
          @mutex.synchronize { @pkce_data[server_url] = pkce }
        end

        def delete_pkce(server_url)
          @mutex.synchronize { @pkce_data.delete(server_url) }
        end

        # State parameter management (temporary)
        def get_state(server_url)
          @mutex.synchronize { @state_data[server_url] }
        end

        def set_state(server_url, state)
          @mutex.synchronize { @state_data[server_url] = state }
        end

        def delete_state(server_url)
          @mutex.synchronize { @state_data.delete(server_url) }
        end

        # Resource metadata management
        def get_resource_metadata(server_url)
          @mutex.synchronize { @resource_metadata[server_url] }
        end

        def set_resource_metadata(server_url, metadata)
          @mutex.synchronize { @resource_metadata[server_url] = metadata }
        end

        def delete_resource_metadata(server_url)
          @mutex.synchronize { @resource_metadata.delete(server_url) }
        end
      end
    end
  end
end
