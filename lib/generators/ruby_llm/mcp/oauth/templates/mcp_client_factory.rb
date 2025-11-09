# frozen_string_literal: true

# Factory for creating per-user MCP clients with OAuth authentication
class McpClientFactory
  class NotAuthenticatedError < StandardError; end

  # Create MCP client for a specific user
  # @param user [User] the user to create client for
  # @param server_url [String] MCP server URL (defaults to ENV var)
  # @param scope [String] OAuth scopes to request (defaults to ENV var)
  # @return [RubyLLM::MCP::Client] configured MCP client
  # @raise [NotAuthenticatedError] if user hasn't connected to MCP server
  def self.for_user(user, server_url: nil, scope: nil)
    server_url ||= ENV.fetch("DEFAULT_MCP_SERVER_URL") { raise "DEFAULT_MCP_SERVER_URL not set" }
    scope ||= ENV["MCP_OAUTH_SCOPES"] || "mcp:read mcp:write"

    unless user.mcp_connected?(server_url)
      raise NotAuthenticatedError,
            "User #{user.id} has not connected to MCP server: #{server_url}. " \
            "Please complete OAuth flow first."
    end

    storage = OauthStorage::UserTokenStorage.new(user.id, server_url)

    RubyLLM::MCP.client(
      name: "user-#{user.id}-#{server_url.hash.abs}",
      transport_type: determine_transport_type(server_url),
      config: {
        url: server_url,
        oauth: {
          storage: storage,
          scope: scope
        }
      }
    )
  end

  # Create MCP client for user, returning nil if not authenticated
  # @param user [User] the user
  # @return [RubyLLM::MCP::Client, nil] client or nil
  def self.for_user_with_fallback(user, server_url: nil)
    for_user(user, server_url: server_url)
  rescue NotAuthenticatedError
    nil
  end

  # Check if user has valid MCP connection
  # @param user [User] the user
  # @param server_url [String] MCP server URL
  # @return [Boolean] true if user has valid token
  def self.connected?(user, server_url: nil)
    server_url ||= ENV.fetch("DEFAULT_MCP_SERVER_URL", nil)
    return false unless server_url

    credential = user.mcp_oauth_credentials.find_by(server_url: server_url)
    credential&.valid_token? || false
  end

  # Determine transport type from URL
  # @param url [String] server URL
  # @return [Symbol] :sse or :streamable
  def self.determine_transport_type(url)
    url.include?("/sse") ? :sse : :streamable
  end

  private_class_method :determine_transport_type
end
