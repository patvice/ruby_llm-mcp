# frozen_string_literal: true

# Controller for managing MCP OAuth connections
class McpConnectionsController < ApplicationController
  before_action :authenticate_user!

  # GET /mcp_connections
  def index
    @credentials = current_user.mcp_oauth_credentials.order(created_at: :desc)
    @server_url = ENV.fetch("DEFAULT_MCP_SERVER_URL", nil)
  end

  # GET /mcp_connections/connect
  def connect
    server_url = params[:server_url] || ENV.fetch("DEFAULT_MCP_SERVER_URL") do
      raise "DEFAULT_MCP_SERVER_URL environment variable not set"
    end
    scope = params[:scope] || ENV["MCP_OAUTH_SCOPES"] || "mcp:read mcp:write"

    # Create user-specific storage
    storage = OauthStorage::UserTokenStorage.new(current_user.id, server_url)

    # Create OAuth provider
    oauth_provider = RubyLLM::MCP::Auth::OAuthProvider.new(
      server_url: server_url,
      redirect_uri: mcp_connections_callback_url,
      scope: scope,
      storage: storage,
      logger: Rails.logger
    )

    # Start OAuth flow
    begin
      auth_url = oauth_provider.start_authorization_flow

      # Store context in session for callback
      session[:mcp_oauth_context] = {
        user_id: current_user.id,
        server_url: server_url,
        scope: scope,
        started_at: Time.current.to_i
      }

      redirect_to auth_url, allow_other_host: true
    rescue StandardError => e
      Rails.logger.error "MCP OAuth flow start failed: #{e.message}"
      redirect_to mcp_connections_path,
                  alert: "Failed to start OAuth flow: #{e.message}"
    end
  end

  # GET /mcp_connections/callback
  def callback
    oauth_context = retrieve_and_validate_oauth_context
    return unless oauth_context

    return if oauth_error_present?

    complete_oauth_flow_for_user(oauth_context)
  end

  private

  def retrieve_and_validate_oauth_context
    oauth_context = session.delete(:mcp_oauth_context)

    unless oauth_context
      redirect_to mcp_connections_path, alert: "OAuth session expired. Please try again."
      return nil
    end

    if oauth_flow_timed_out?(oauth_context)
      redirect_to mcp_connections_path, alert: "OAuth flow timed out. Please try again."
      return nil
    end

    oauth_context
  end

  def oauth_flow_timed_out?(context)
    Time.current.to_i - context["started_at"] > 600
  end

  def oauth_error_present?
    return false unless params[:error]

    error_message = params[:error_description] || params[:error]
    redirect_to mcp_connections_path, alert: "OAuth authorization failed: #{error_message}"
    true
  end

  def complete_oauth_flow_for_user(oauth_context)
    oauth_provider = create_oauth_provider_from_context(oauth_context)

    oauth_provider.complete_authorization_flow(params[:code], params[:state])
    log_successful_oauth(oauth_context)
    redirect_after_success
  rescue StandardError => e
    handle_oauth_callback_error(e)
  end

  def create_oauth_provider_from_context(oauth_context)
    storage = OauthStorage::UserTokenStorage.new(
      oauth_context["user_id"],
      oauth_context["server_url"]
    )

    RubyLLM::MCP::Auth::OAuthProvider.new(
      server_url: oauth_context["server_url"],
      redirect_uri: mcp_connections_callback_url,
      scope: oauth_context["scope"],
      storage: storage,
      logger: Rails.logger
    )
  end

  def log_successful_oauth(oauth_context)
    Rails.logger.info "MCP OAuth completed for user #{current_user.id}, " \
                      "server: #{oauth_context['server_url']}"
  end

  def redirect_after_success
    return_path = session.delete(:mcp_return_to) || mcp_connections_path
    redirect_to return_path, notice: "Successfully connected to MCP server!"
  end

  def handle_oauth_callback_error(error)
    Rails.logger.error "MCP OAuth callback failed: #{error.message}"
    redirect_to mcp_connections_path, alert: "OAuth authorization failed: #{error.message}"
  end

  public

  # DELETE /mcp_connections/:id/disconnect
  def disconnect
    credential = current_user.mcp_oauth_credentials.find(params[:id])
    server_url = credential.server_url
    credential.destroy

    Rails.logger.info "User #{current_user.id} disconnected from MCP server: #{server_url}"

    redirect_to mcp_connections_path,
                notice: "MCP server disconnected successfully"
  rescue ActiveRecord::RecordNotFound
    redirect_to mcp_connections_path,
                alert: "Connection not found"
  end

  # GET /mcp_connections/:id/refresh
  def refresh
    credential = current_user.mcp_oauth_credentials.find(params[:id])

    storage = OauthStorage::UserTokenStorage.new(current_user.id, credential.server_url)
    oauth_provider = RubyLLM::MCP::Auth::OAuthProvider.new(
      server_url: credential.server_url,
      storage: storage
    )

    # Trigger token refresh
    refreshed_token = oauth_provider.access_token

    if refreshed_token
      redirect_to mcp_connections_path,
                  notice: "Token refreshed successfully"
    else
      redirect_to mcp_connections_path,
                  alert: "Token refresh failed. Please reconnect."
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to mcp_connections_path,
                alert: "Connection not found"
  end
end
