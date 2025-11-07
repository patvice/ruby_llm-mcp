# frozen_string_literal: true

# Add this to your User model:
# include UserMcpOauth

module UserMcpOauth
  extend ActiveSupport::Concern

  included do
    has_many :mcp_oauth_credentials, dependent: :destroy
    has_many :mcp_oauth_states, dependent: :destroy
  end

  # Check if user has connected to a specific MCP server
  # @param server_url [String] MCP server URL (defaults to ENV var)
  # @return [Boolean] true if user has an OAuth credential for this server
  def mcp_connected?(server_url = nil)
    server_url ||= ENV.fetch("DEFAULT_MCP_SERVER_URL", nil)
    return false unless server_url

    mcp_oauth_credentials.exists?(server_url: server_url)
  end

  # Get valid token for a server
  # @param server_url [String] MCP server URL
  # @return [RubyLLM::MCP::Auth::Token, nil] token if valid, nil otherwise
  def mcp_token_for(server_url = nil)
    server_url ||= ENV.fetch("DEFAULT_MCP_SERVER_URL", nil)
    return nil unless server_url

    credential = mcp_oauth_credentials.find_by(server_url: server_url)
    return nil unless credential

    token = credential.token
    return nil if token.nil? || token.expired? || token.expires_soon?

    token
  end

  # Get MCP client for this user
  # @param server_url [String] MCP server URL
  # @return [RubyLLM::MCP::Client] configured client
  # @raise [McpClientFactory::NotAuthenticatedError] if not connected
  def mcp_client(server_url: nil)
    McpClientFactory.for_user(self, server_url: server_url)
  end

  # Get MCP client with fallback to nil if not authenticated
  # @param server_url [String] MCP server URL
  # @return [RubyLLM::MCP::Client, nil] client or nil
  def mcp_client_safe(server_url: nil)
    McpClientFactory.for_user_with_fallback(self, server_url: server_url)
  end

  # Get all connected MCP servers for this user
  # @return [Array<String>] array of server URLs
  def connected_mcp_servers
    mcp_oauth_credentials.pluck(:server_url)
  end

  # Disconnect from a specific MCP server
  # @param server_url [String] MCP server URL
  def revoke_mcp_connection(server_url)
    credential = mcp_oauth_credentials.find_by(server_url: server_url)
    credential&.destroy
  end

  # Get OAuth connection status for a server
  # @param server_url [String] MCP server URL
  # @return [Hash] status information
  def mcp_connection_status(server_url = nil)
    server_url ||= ENV.fetch("DEFAULT_MCP_SERVER_URL", nil)
    credential = mcp_oauth_credentials.find_by(server_url: server_url)

    return { connected: false } unless credential

    token = credential.token

    {
      connected: true,
      valid: token && !token.expired?,
      expires_at: token&.expires_at,
      expires_soon: token&.expires_soon?,
      has_refresh_token: token&.refresh_token.present?,
      last_refreshed_at: credential.last_refreshed_at,
      scope: token&.scope
    }
  end
end
