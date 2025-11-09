# frozen_string_literal: true

module OauthStorage
  # Per-user OAuth token storage for RubyLLM MCP
  # Implements the storage interface required by RubyLLM::MCP::Auth::OAuthProvider
  class UserTokenStorage
    def initialize(user_id, server_url)
      @user_id = user_id
      @server_url = server_url
    end

    # Token storage
    def get_token(_server_url)
      credential = McpOauthCredential.find_by(user_id: @user_id, server_url: @server_url)
      credential&.token
    end

    def set_token(_server_url, token)
      credential = McpOauthCredential.find_or_initialize_by(
        user_id: @user_id,
        server_url: @server_url
      )
      credential.token = token
      credential.last_refreshed_at = Time.current
      credential.save!
    end

    # Client registration storage
    def get_client_info(_server_url)
      credential = McpOauthCredential.find_by(user_id: @user_id, server_url: @server_url)
      credential&.client_info
    end

    def set_client_info(_server_url, client_info)
      credential = McpOauthCredential.find_or_initialize_by(
        user_id: @user_id,
        server_url: @server_url
      )
      credential.client_info = client_info
      credential.save!
    end

    # Server metadata caching (shared across users)
    def get_server_metadata(server_url)
      Rails.cache.fetch("mcp:server_metadata:#{server_url}", expires_in: 24.hours) do
        nil
      end
    end

    def set_server_metadata(server_url, metadata)
      Rails.cache.write("mcp:server_metadata:#{server_url}", metadata, expires_in: 24.hours)
    end

    # PKCE state management (temporary - per user)
    def get_pkce(_server_url)
      state = McpOauthState.find_by(user_id: @user_id, server_url: @server_url)
      return nil unless state

      state.pkce
    end

    def set_pkce(_server_url, pkce)
      state = McpOauthState.find_or_initialize_by(user_id: @user_id, server_url: @server_url)
      state.pkce = pkce
      state.state_param ||= SecureRandom.hex(32)
      state.expires_at ||= 10.minutes.from_now
      state.save!
    end

    def delete_pkce(_server_url)
      McpOauthState.where(user_id: @user_id, server_url: @server_url).delete_all
    end

    # State parameter management
    def get_state(_server_url)
      McpOauthState.find_by(user_id: @user_id, server_url: @server_url)&.state_param
    end

    def set_state(_server_url, state_param)
      state = McpOauthState.find_or_initialize_by(user_id: @user_id, server_url: @server_url)
      state.state_param = state_param
      state.expires_at ||= 10.minutes.from_now
      state.save!
    end

    def delete_state(_server_url)
      McpOauthState.where(user_id: @user_id, server_url: @server_url).delete_all
    end
  end
end
