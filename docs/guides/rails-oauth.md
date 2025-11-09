---
layout: default
title: Rails OAuth Integration
parent: Guides
nav_order: 10
description: "Multi-user OAuth authentication for Rails apps with background jobs and per-user MCP permissions"
---

# Rails OAuth Integration
{: .no_toc }

Complete guide for implementing multi-tenant OAuth authentication in Rails applications, enabling per-user MCP server connections with background job support.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

This guide covers implementing OAuth authentication for MCP servers in a Rails application where:
- Multiple users need their own MCP connections
- Background jobs run with user-specific permissions
- Tokens are stored securely per-user
- OAuth flow happens in the user's browser
- Background workers use stored tokens (no browser needed)

### Architecture Pattern

```
User Browser (Foreground)          Background Jobs (Headless)
─────────────────────────          ─────────────────────────
1. Click "Connect MCP"             4. Job starts with user_id
2. OAuth authorization      ──→    5. Load user's token
3. Token stored in DB              6. Create MCP client
                                   7. Execute with user permissions
```

## Quick Start

### Step 1: Run the Generator

```bash
# Basic installation (uses User model)
rails generate ruby_llm:mcp:oauth:install

# Custom user model
rails generate ruby_llm:mcp:oauth:install Account

# With namespace
rails generate ruby_llm:mcp:oauth:install User --namespace=Admin

# Custom controller name
rails generate ruby_llm:mcp:oauth:install User --controller-name=OAuthConnectionsController

# Skip automatic route injection
rails generate ruby_llm:mcp:oauth:install User --skip-routes

# Skip view generation
rails generate ruby_llm:mcp:oauth:install User --skip-views
```

This creates:
- Database migrations for OAuth credentials
- Models (`McpOauthCredential`, `McpOauthState`)
- Controller (`McpConnectionsController` or custom name)
- Token storage concern (`McpTokenStorage`)
- User concern for OAuth methods (`UserMcpOauth`)
- MCP client class (`McpClient`)
- Routes for OAuth flow (automatically injected unless `--skip-routes`)
- Example background job
- Cleanup job for expired OAuth states

### Step 2: Run Migrations

```bash
rails db:migrate
```

### Step 3: Configure Your MCP Server

```ruby
# config/initializers/ruby_llm_mcp.rb
ENV["DEFAULT_MCP_SERVER_URL"] = "https://mcp.example.com/api"
ENV["MCP_OAUTH_SCOPES"] = "mcp:read mcp:write"
```

### Step 4: Add User Association

```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_many :mcp_oauth_credentials, dependent: :destroy
  has_many :mcp_oauth_states, dependent: :destroy

  def mcp_connected?(server_url = ENV["DEFAULT_MCP_SERVER_URL"])
    mcp_oauth_credentials.exists?(server_url: server_url)
  end
end
```

### Step 5: Use in Your App

```ruby
# User connects (browser-based)
# Visit: /mcp_connections/connect

# Background job (no browser)
class AiResearchJob < ApplicationJob
  def perform(user_id, query)
    user = User.find(user_id)
    client = McpClient.for(user)

    tools = client.tools
    chat = RubyLLM.chat(provider: "anthropic/claude-sonnet-4")
      .with_tools(*tools)

    response = chat.ask(query)
    # ... save results ...
  end
end
```

## Generator Customization

The generator supports full customization for different application architectures:

### Custom User Model

If your application uses a different model for authentication (e.g., `Account`, `Member`):

```bash
rails generate ruby_llm:mcp:oauth:install Account
```

This automatically:
- Updates foreign keys in migrations (`account_id` instead of `user_id`)
- Adjusts model associations (`belongs_to :account`)
- Updates controller authentication (`current_account`, `authenticate_account!`)
- Customizes service methods (`McpClient.for(account)`)

### Namespaced Installation

For admin or multi-tenant applications:

```bash
rails generate ruby_llm:mcp:oauth:install User --namespace=Admin
```

This creates:
- Controllers in `app/controllers/admin/mcp_connections_controller.rb`
- Views in `app/views/admin/mcp_connections/`
- Routes under `/admin/mcp_connections`

### Options Reference

| Option | Description | Example |
|--------|-------------|---------|
| `UserModel` | Authentication model name | `Account`, `Member`, `Admin` |
| `--namespace` | Namespace for controllers/views | `--namespace=Admin` |
| `--controller-name` | Custom controller name | `--controller-name=OAuthConnectionsController` |
| `--skip-routes` | Don't inject routes automatically | `--skip-routes` |
| `--skip-views` | Don't generate view files | `--skip-views` |

## Complete Architecture

### Database Schema

The generator creates these tables:

**mcp_oauth_credentials** - Stores user's OAuth tokens
```ruby
t.references :user, null: false, foreign_key: true
t.string :server_url, null: false
t.text :token_data, null: false      # Encrypted JSON
t.text :client_info_data             # Encrypted client credentials
t.datetime :token_expires_at
t.datetime :last_refreshed_at
t.index [:user_id, :server_url], unique: true
```

**mcp_oauth_states** - Temporary OAuth flow state
```ruby
t.references :user, null: false, foreign_key: true
t.string :server_url, null: false
t.string :state_param, null: false
t.text :pkce_data, null: false       # Encrypted PKCE verifier
t.datetime :expires_at, null: false
t.index [:user_id, :state_param], unique: true
```

### Models

#### McpOauthCredential

```ruby
class McpOauthCredential < ApplicationRecord
  belongs_to :user

  encrypts :token_data
  encrypts :client_info_data

  validates :server_url, presence: true, uniqueness: { scope: :user_id }

  def token
    return nil unless token_data.present?
    RubyLLM::MCP::Auth::Token.from_h(JSON.parse(token_data, symbolize_names: true))
  end

  def token=(token)
    self.token_data = token.to_h.to_json
    self.token_expires_at = token.expires_at
  end

  def expired?
    token&.expired?
  end

  def expires_soon?
    token&.expires_soon?
  end
end
```

#### McpOauthState

```ruby
class McpOauthState < ApplicationRecord
  belongs_to :user
  encrypts :pkce_data

  validates :state_param, presence: true

  scope :expired, -> { where("expires_at < ?", Time.current) }

  def self.cleanup_expired
    expired.delete_all
  end
end
```

### Token Storage Concern

#### McpTokenStorage

A concern that provides OAuth token storage capabilities to any model (typically User):

```ruby
# app/models/concerns/mcp_token_storage.rb
module McpTokenStorage
  extend ActiveSupport::Concern

  # Create token storage instance for a specific server URL
  def mcp_token_storage(server_url)
    TokenStorageAdapter.new(self.id, server_url, self.class.name.underscore)
  end

  # Internal adapter class that implements the OAuth storage interface
  class TokenStorageAdapter
    def initialize(user_id, server_url, user_type = "user")
      @user_id = user_id
      @server_url = server_url
      @user_type = user_type
    end

    def get_token(_server_url)
      credential = McpOauthCredential.find_by(
        user_id: @user_id,
        server_url: @server_url
      )
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

    # Implements full storage interface...
  end
end
```

This concern is automatically included via the `UserMcpOauth` concern:

```ruby
# app/models/user.rb
class User < ApplicationRecord
  include UserMcpOauth  # This includes McpTokenStorage
end

# Now you can use it directly:
user.mcp_token_storage(server_url)
```

### Controller

#### McpConnectionsController

Handles OAuth flow:

```ruby
class McpConnectionsController < ApplicationController
  before_action :authenticate_user!

  def index
    @credentials = current_user.mcp_oauth_credentials
  end

  def connect
    # Start OAuth flow
    oauth_provider = create_oauth_provider_for_user
    session[:mcp_oauth_context] = oauth_context
    redirect_to oauth_provider.start_authorization_flow, allow_other_host: true
  end

  def callback
    # Complete OAuth flow
    oauth_provider = recreate_oauth_provider_from_session
    token = oauth_provider.complete_authorization_flow(params[:code], params[:state])

    redirect_to mcp_connections_path,
                notice: "MCP server connected successfully!"
  end

  def disconnect
    current_user.mcp_oauth_credentials.find(params[:id]).destroy
    redirect_to mcp_connections_path, notice: "Disconnected"
  end
end
```

## Usage Patterns

### Pattern 1: Background Jobs (Recommended)

```ruby
class AiAnalysisJob < ApplicationJob
  queue_as :default

  def perform(user_id, analysis_params)
    user = User.find(user_id)

    # Create MCP client with user's OAuth token
    client = McpClient.for(user)

    # Use client with user's permissions
    tools = client.tools
    chat = RubyLLM.chat(provider: "anthropic/claude-sonnet-4")
      .with_tools(*tools)

    result = chat.ask(analysis_params[:query])

    # Save results associated with user
    user.analysis_results.create!(
      query: analysis_params[:query],
      result: result.text
    )
  ensure
    client&.stop
  end
end

# Enqueue from controller
class AnalysisController < ApplicationController
  def create
    ensure_mcp_connected!

    AiAnalysisJob.perform_later(current_user.id, analysis_params)
    redirect_to analyses_path, notice: "Analysis started!"
  end

  private

  def ensure_mcp_connected!
    unless current_user.mcp_connected?
      redirect_to connect_mcp_connections_path,
                  alert: "Please connect MCP server first"
    end
  end
end
```

### Pattern 2: Inline (Synchronous)

```ruby
class SearchController < ApplicationController
  def create
    ensure_mcp_connected!

    client = McpClient.for(current_user)

    result = client.tool("search").execute(
      params: { query: params[:query] }
    )

    render json: { results: result }
  ensure
    client&.stop
  end
end
```

### Pattern 3: Streaming with ActionCable

```ruby
class StreamingAnalysisChannel < ApplicationCable::Channel
  def subscribed
    stream_from "analysis_#{current_user.id}"
  end

  def analyze(data)
    AnalyzeStreamJob.perform_later(current_user.id, data["query"])
  end
end

class AnalyzeStreamJob < ApplicationJob
  def perform(user_id, query)
    user = User.find(user_id)
    client = McpClient.for(user)

    chat = RubyLLM.chat(provider: "anthropic/claude-sonnet-4")
      .with_tools(*client.tools)

    chat.ask(query) do |chunk|
      # Stream to user via ActionCable
      ActionCable.server.broadcast(
        "analysis_#{user_id}",
        { type: "chunk", content: chunk.content }
      )
    end
  end
end
```

## Client Factory Pattern

### McpClient

The generator creates an `McpClient` class that provides a simple interface for creating per-user MCP clients:

```ruby
# app/lib/mcp_client.rb
class McpClient
  class NotAuthenticatedError < StandardError; end

  def self.for(user, server_url: nil, scope: nil)
    server_url ||= ENV["DEFAULT_MCP_SERVER_URL"]
    scope ||= ENV["MCP_OAUTH_SCOPES"]

    unless user.mcp_connected?(server_url)
      raise NotAuthenticatedError,
            "User has not connected to MCP server: #{server_url}"
    end

    storage = user.mcp_token_storage(server_url)

    RubyLLM::MCP.client(
      name: "user-#{user.id}-#{server_url.hash}",
      transport_type: :sse,  # or :streamable
      config: {
        url: server_url,
        oauth: {
          storage: storage,
          scope: scope
        }
      }
    )
  end

  def self.for_with_fallback(user, server_url: nil)
    self.for(user, server_url: server_url)
  rescue NotAuthenticatedError
    nil
  end
end
```

You can also access the client directly via the user model:

```ruby
# Using McpClient class directly
client = McpClient.for(user)

# Or via the user model (same result)
client = user.mcp_client
```

## User Flow Examples

### Example 1: Onboarding Flow

```ruby
# app/controllers/onboarding_controller.rb
class OnboardingController < ApplicationController
  def integrations
    @mcp_servers = [
      {
        name: "Research Database",
        url: ENV["RESEARCH_MCP_URL"],
        description: "Access to research papers and data",
        connected: current_user.mcp_connected?(ENV["RESEARCH_MCP_URL"])
      }
    ]
  end

  def skip_integrations
    session[:onboarding_step] = :completed
    redirect_to dashboard_path
  end
end
```

```erb
<!-- app/views/onboarding/integrations.html.erb -->
<h1>Connect Your AI Tools</h1>

<% @mcp_servers.each do |server| %>
  <div class="card">
    <h3><%= server[:name] %></h3>
    <p><%= server[:description] %></p>

    <% if server[:connected] %>
      <span class="badge badge-success">✓ Connected</span>
    <% else %>
      <%= link_to "Connect",
          connect_mcp_connections_path(server_url: server[:url]),
          class: "btn btn-primary" %>
    <% end %>
  </div>
<% end %>

<%= link_to "Skip for now", skip_integrations_path, class: "btn btn-link" %>
```

### Example 2: Feature-Gated Access

```ruby
# app/controllers/ai_features_controller.rb
class AiFeaturesController < ApplicationController
  before_action :require_mcp_connection, only: [:create, :update]

  def create
    AiProcessingJob.perform_later(current_user.id, feature_params)
    redirect_to ai_features_path, notice: "Processing started!"
  end

  private

  def require_mcp_connection
    return if current_user.mcp_connected?

    session[:return_to] = request.fullpath
    redirect_to connect_mcp_connections_path,
                alert: "Please connect MCP server to use this feature"
  end
end

# In callback controller:
def callback
  # ... complete OAuth ...

  if session[:return_to]
    redirect_to session.delete(:return_to)
  else
    redirect_to mcp_connections_path
  end
end
```

### Example 3: Multi-Server Support

```ruby
# app/models/mcp_server.rb
class McpServer
  SERVERS = {
    github: {
      url: ENV["GITHUB_MCP_URL"],
      name: "GitHub",
      scopes: "mcp:repos mcp:issues"
    },
    slack: {
      url: ENV["SLACK_MCP_URL"],
      name: "Slack",
      scopes: "mcp:messages mcp:channels"
    },
    notion: {
      url: ENV["NOTION_MCP_URL"],
      name: "Notion",
      scopes: "mcp:pages mcp:databases"
    }
  }.freeze

  def self.all
    SERVERS.values
  end

  def self.for(key)
    SERVERS[key.to_sym]
  end
end

# Controller
class McpConnectionsController < ApplicationController
  def connect
    server_key = params[:server]
    server_config = McpServer.for(server_key)

    raise "Unknown server" unless server_config

    # Create OAuth provider with server-specific scopes
    oauth_provider = RubyLLM::MCP::Auth::OAuthProvider.new(
      server_url: server_config[:url],
      redirect_uri: mcp_connections_callback_url,
      scope: server_config[:scopes],
      storage: current_user.mcp_token_storage(server_config[:url])
    )

    session[:mcp_oauth_context] = {
      user_id: current_user.id,
      server_url: server_config[:url],
      server_key: server_key
    }

    redirect_to oauth_provider.start_authorization_flow, allow_other_host: true
  end
end

# Usage in jobs
class MultiServerJob < ApplicationJob
  def perform(user_id, task)
    user = User.find(user_id)

    github = create_client(user, :github)
    slack = create_client(user, :slack)

    chat = RubyLLM.chat(provider: "anthropic/claude-sonnet-4")
      .with_tools(*github.tools, *slack.tools)

    response = chat.ask(task)
  end

  def create_client(user, server_key)
    config = McpServer.for(server_key)
    McpClient.for(user, server_url: config[:url])
  end
end
```

## Advanced Patterns

### Scoped Access by User Role

```ruby
# app/lib/mcp_client.rb
ROLE_SCOPES = {
  viewer: "mcp:read",
  editor: "mcp:read mcp:write",
  admin: "mcp:read mcp:write mcp:admin"
}.freeze

def self.for(user, server_url: nil)
  server_url ||= ENV["DEFAULT_MCP_SERVER_URL"]
  scope = ROLE_SCOPES[user.role.to_sym] || ROLE_SCOPES[:viewer]

  RubyLLM::MCP.client(
    name: "user-#{user.id}-mcp",
    transport_type: :sse,
    config: {
      url: server_url,
      oauth: {
        storage: user.mcp_token_storage(server_url),
        scope: scope
      }
    }
  )
end
```

### Proactive Token Refresh

```ruby
# app/jobs/refresh_mcp_tokens_job.rb
class RefreshMcpTokensJob < ApplicationJob
  queue_as :low_priority

  def perform
    # Refresh tokens expiring within 1 hour
    McpOauthCredential
      .where("token_expires_at < ?", 1.hour.from_now)
      .where("token_expires_at > ?", Time.current)
      .find_each do |credential|

      refresh_user_token(credential)
    end
  end

  private

  def refresh_user_token(credential)
    user = User.find(credential.user_id)

    oauth_provider = RubyLLM::MCP::Auth::OAuthProvider.new(
      server_url: credential.server_url,
      storage: user.mcp_token_storage(credential.server_url)
    )

    refreshed = oauth_provider.access_token

    if refreshed
      Rails.logger.info "Refreshed MCP token for user #{credential.user_id}"
    else
      notify_reauth_needed(credential.user)
    end
  end

  def notify_reauth_needed(user)
    UserMailer.mcp_reauth_required(user).deliver_later
  end
end

# Schedule hourly
# config/schedule.rb (whenever gem)
every 1.hour do
  runner "RefreshMcpTokensJob.perform_later"
end
```

### Health Checks

```ruby
# app/services/mcp_health_check.rb
class McpHealthCheck
  def self.for_user(user, server_url: nil)
    server_url ||= ENV["DEFAULT_MCP_SERVER_URL"]
    credential = user.mcp_oauth_credentials.find_by(server_url: server_url)

    return { connected: false } unless credential

    token = credential.token

    {
      connected: true,
      valid: token && !token.expired?,
      expires_at: token&.expires_at,
      expires_soon: token&.expires_soon?,
      has_refresh_token: token&.refresh_token.present?
    }
  end

  def self.alert_expiring_tokens
    credentials = McpOauthCredential
      .where("token_expires_at < ?", 24.hours.from_now)
      .where("token_expires_at > ?", Time.current)

    credentials.each do |credential|
      token = credential.token
      next if token&.refresh_token.present?  # Can auto-refresh

      # No refresh token - user must re-auth
      UserMailer.mcp_expiring_soon(credential.user).deliver_later
    end
  end
end
```

## UI Components

### Connection Status Badge

```erb
<!-- app/views/shared/_mcp_status.html.erb -->
<% status = McpHealthCheck.for_user(current_user) %>

<div class="mcp-status">
  <% if status[:connected] %>
    <% if status[:valid] %>
      <span class="badge badge-success">
        ✓ MCP Connected
      </span>
      <small class="text-muted">
        Expires <%= time_ago_in_words(status[:expires_at]) %> from now
      </small>
    <% else %>
      <span class="badge badge-danger">
        ✗ Token Expired
      </span>
      <%= link_to "Reconnect", connect_mcp_connections_path, class: "btn btn-sm" %>
    <% end %>
  <% else %>
    <span class="badge badge-secondary">
      Not Connected
    </span>
    <%= link_to "Connect MCP", connect_mcp_connections_path, class: "btn btn-sm btn-primary" %>
  <% end %>
</div>
```

### Settings Page

```erb
<!-- app/views/settings/integrations.html.erb -->
<h1>Integrations</h1>

<div class="integration-list">
  <h2>MCP Servers</h2>

  <% if current_user.mcp_oauth_credentials.any? %>
    <table class="table">
      <thead>
        <tr>
          <th>Server</th>
          <th>Status</th>
          <th>Scopes</th>
          <th>Expires</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <% current_user.mcp_oauth_credentials.each do |cred| %>
          <tr>
            <td><%= cred.server_url %></td>
            <td>
              <% if cred.expired? %>
                <span class="badge badge-danger">Expired</span>
              <% elsif cred.expires_soon? %>
                <span class="badge badge-warning">Expiring Soon</span>
              <% else %>
                <span class="badge badge-success">Active</span>
              <% end %>
            </td>
            <td><code><%= cred.token&.scope || "N/A" %></code></td>
            <td>
              <% if cred.token_expires_at %>
                <%= cred.token_expires_at.to_s(:short) %>
              <% else %>
                Never
              <% end %>
            </td>
            <td>
              <%= button_to "Disconnect",
                  disconnect_mcp_connection_path(cred),
                  method: :delete,
                  data: { confirm: "Are you sure?" },
                  class: "btn btn-sm btn-danger" %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% else %>
    <p class="text-muted">No MCP servers connected</p>
  <% end %>

  <h3>Add Server</h3>
  <%= link_to "Connect MCP Server",
      connect_mcp_connections_path,
      class: "btn btn-primary" %>
</div>
```

## Security Best Practices

### 1. Encrypt Sensitive Data

```ruby
# config/application.rb
config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]

# Models use:
encrypts :token_data
encrypts :client_info_data
```

### 2. Validate Redirect URIs

```ruby
# config/initializers/ruby_llm_mcp_oauth.rb
ALLOWED_REDIRECT_URIS = [
  "http://localhost:3000/mcp_connections/callback",           # Development
  "https://staging.myapp.com/mcp_connections/callback",       # Staging
  "https://app.myapp.com/mcp_connections/callback"            # Production
].freeze

def validate_redirect_uri!
  uri = mcp_connections_callback_url
  unless ALLOWED_REDIRECT_URIS.include?(uri)
    raise "Invalid redirect URI: #{uri}"
  end
end
```

### 3. CSRF Protection

Rails CSRF protection works automatically since OAuth state parameter is stored in session.

### 4. Rate Limiting

Rails 8+ includes built-in rate limiting in ActionController. The generator automatically adds protection against OAuth abuse:

```ruby
# app/controllers/mcp_connections_controller.rb
class McpConnectionsController < ApplicationController
  before_action :authenticate_user!

  # Prevent burst requests - max 5 connection attempts per minute
  rate_limit to: 5, within: 1.minute, only: [:connect, :callback],
             by: -> { current_user.id },
             name: "mcp_oauth_burst",
             with: -> {
               redirect_to mcp_connections_path,
                           alert: "Too many connection attempts. Please wait a moment and try again."
             }

  # Prevent abuse - max 20 connection attempts per day
  rate_limit to: 20, within: 1.day, only: [:connect, :callback],
             by: -> { current_user.id },
             name: "mcp_oauth_daily",
             with: -> {
               redirect_to mcp_connections_path,
                           alert: "Daily connection limit reached. Please try again tomorrow."
             }

  # ... rest of controller ...
end
```

This provides two-tier protection:
- **Short-term**: Prevents rapid-fire attempts (5 per minute)
- **Long-term**: Prevents daily abuse (20 per day)

Both limits are per-user (by `current_user.id`) and include custom redirect messages when exceeded.

**For Rails 7 and earlier**, use Rack::Attack or a custom implementation:

```ruby
# config/initializers/rack_attack.rb (Rails 7 and earlier)
class Rack::Attack
  throttle("mcp_oauth/ip", limit: 5, period: 1.hour) do |req|
    if req.path.start_with?("/mcp_connections/connect")
      req.ip
    end
  end
end
```

## Error Handling

### Graceful Degradation

```ruby
# app/jobs/ai_task_job.rb
def perform(user_id, task)
  user = User.find(user_id)

  begin
    client = McpClient.for(user)
    # ... execute task ...
  rescue McpClient::NotAuthenticatedError
    # User not connected - notify them
    notify_auth_required(user)
  rescue RubyLLM::MCP::Errors::TransportError => e
    if unauthorized_error?(e)
      # Token invalid - notify user to reconnect
      notify_reauth_required(user)
    else
      raise
    end
  ensure
    client&.stop
  end
end

def unauthorized_error?(error)
  error.message.include?("401") ||
  error.message.include?("Unauthorized") ||
  error.message.include?("invalid_token")
end

def notify_auth_required(user)
  ActionCable.server.broadcast("user_#{user.id}", {
    type: "mcp_auth_required",
    message: "Connect MCP server to continue",
    action_url: connect_mcp_connections_url
  })
end
```

### Retry Logic

```ruby
class AiTaskJob < ApplicationJob
  retry_on McpClient::NotAuthenticatedError,
           wait: :polynomially_longer,
           attempts: 3 do |job, exception|
    # After retries, notify user
    user = User.find(job.arguments.first)
    UserMailer.task_failed_auth(user).deliver_now
  end

  retry_on RubyLLM::MCP::Errors::TransportError,
           wait: 5.seconds,
           attempts: 2
end
```

## Testing

### RSpec Setup

```ruby
# spec/support/mcp_oauth_helpers.rb
module McpOauthHelpers
  def create_mcp_credential_for(user, server_url: nil, expires_in: 3600)
    server_url ||= "https://test-mcp.example.com"

    token = RubyLLM::MCP::Auth::Token.new(
      access_token: "test_token_#{SecureRandom.hex(8)}",
      token_type: "Bearer",
      expires_in: expires_in,
      scope: "mcp:read mcp:write",
      refresh_token: "refresh_#{SecureRandom.hex(8)}"
    )

    McpOauthCredential.create!(
      user: user,
      server_url: server_url,
      token: token
    )
  end
end

RSpec.configure do |config|
  config.include McpOauthHelpers
end
```

### Controller Tests

```ruby
# spec/controllers/mcp_connections_controller_spec.rb
RSpec.describe McpConnectionsController do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET #connect" do
    it "redirects to OAuth authorization URL" do
      get :connect, params: { server_url: "https://mcp.example.com" }

      expect(response).to redirect_to(/https:\/\/.*\/authorize/)
      expect(session[:mcp_oauth_context]).to be_present
    end
  end

  describe "GET #callback" do
    before do
      session[:mcp_oauth_context] = {
        user_id: user.id,
        server_url: "https://mcp.example.com"
      }
    end

    it "creates OAuth credential on success" do
      # Mock OAuth flow
      allow_any_instance_of(RubyLLM::MCP::Auth::OAuthProvider)
        .to receive(:complete_authorization_flow)
        .and_return(double(access_token: "token"))

      expect {
        get :callback, params: { code: "auth_code", state: "state123" }
      }.to change { user.mcp_oauth_credentials.count }.by(1)
    end
  end
end
```

### Job Tests

```ruby
# spec/jobs/ai_analysis_job_spec.rb
RSpec.describe AiAnalysisJob do
  let(:user) { create(:user) }

  context "when user has MCP credentials" do
    before do
      create_mcp_credential_for(user)
    end

    it "executes successfully" do
      VCR.use_cassette("mcp_analysis") do
        expect {
          described_class.perform_now(user.id, { query: "Test" })
        }.not_to raise_error
      end
    end
  end

  context "when user lacks MCP credentials" do
    it "raises NotAuthenticatedError" do
      expect {
        described_class.perform_now(user.id, { query: "Test" })
      }.to raise_error(McpClient::NotAuthenticatedError)
    end
  end
end
```

## Monitoring and Observability

### Connection Status Dashboard

```ruby
# app/controllers/admin/mcp_dashboard_controller.rb
class Admin::McpDashboardController < AdminController
  def index
    @stats = {
      total_users: User.count,
      connected_users: McpOauthCredential.distinct.count(:user_id),
      active_tokens: McpOauthCredential.joins(:user).where("token_expires_at > ?", Time.current).count,
      expiring_soon: McpOauthCredential.where("token_expires_at < ?", 24.hours.from_now).count,
      expired: McpOauthCredential.joins(:user).where("token_expires_at < ?", Time.current).count
    }

    @recent_connections = McpOauthCredential.order(created_at: :desc).limit(10)
  end
end
```

### Prometheus Metrics

```ruby
# config/initializers/prometheus.rb
require "prometheus_exporter/instrumentation"

PrometheusExporter::Instrumentation::Process.start(type: "sidekiq")

# Custom MCP metrics
MCP_OAUTH_CONNECTIONS = PrometheusExporter::Metric::Gauge.new(
  "mcp_oauth_connections_total",
  "Total number of MCP OAuth connections"
)

MCP_OAUTH_ACTIVE = PrometheusExporter::Metric::Gauge.new(
  "mcp_oauth_active_tokens",
  "Number of active MCP OAuth tokens"
)

# Update metrics periodically
class UpdateMcpMetricsJob < ApplicationJob
  def perform
    MCP_OAUTH_CONNECTIONS.observe(McpOauthCredential.count)
    MCP_OAUTH_ACTIVE.observe(
      McpOauthCredential.where("token_expires_at > ?", Time.current).count
    )
  end
end
```

## Troubleshooting

### Common Issues

#### User Can't Connect

**Symptom:** OAuth flow fails with "invalid_redirect_uri"

**Solution:**
```ruby
# Check your redirect URI matches exactly
puts mcp_connections_callback_url
# => "https://app.example.com/mcp_connections/callback"

# Must match what's configured in MCP OAuth server
# No trailing slash, exact protocol (http vs https)
```

#### Token Refresh Fails

**Symptom:** Jobs fail with 401 Unauthorized

**Solution:**
```ruby
# Check if credential has refresh token
credential = user.mcp_oauth_credentials.first
if credential.token.refresh_token.nil?
  # User must re-authenticate
  UserMailer.mcp_reauth_required(user).deliver_now
end
```

#### Session Lost During OAuth

**Symptom:** Callback fails with "OAuth session expired"

**Solution:**
```ruby
# Increase session timeout
# config/initializers/session_store.rb
Rails.application.config.session_store :cookie_store,
  key: '_myapp_session',
  expire_after: 30.minutes  # OAuth flow timeout
```

## Production Deployment

### Environment Variables

```bash
# .env.production
DEFAULT_MCP_SERVER_URL=https://mcp.production.com/api
MCP_OAUTH_SCOPES=mcp:read mcp:write

# Encryption keys
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=...
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=...
```

### Deployment Checklist

- [ ] Run migrations: `rails db:migrate`
- [ ] Set encryption keys in production
- [ ] Configure allowed redirect URIs
- [ ] Set up background job for token refresh
- [ ] Configure monitoring/alerts for token expiration
- [ ] Test OAuth flow in staging
- [ ] Set up cleanup job for expired OAuth states

### Cleanup Jobs

```ruby
# app/jobs/cleanup_expired_oauth_states_job.rb
class CleanupExpiredOauthStatesJob < ApplicationJob
  queue_as :maintenance

  def perform
    deleted = McpOauthState.cleanup_expired
    Rails.logger.info "Cleaned up #{deleted} expired OAuth states"
  end
end

# Schedule daily
every 1.day, at: "3:00 am" do
  runner "CleanupExpiredOauthStatesJob.perform_later"
end
```

## Migration from Simple Auth

If you're migrating from simple token-based auth:

### Before (Simple Headers)
```ruby
# config/mcps.yml
mcp_servers:
  api_server:
    transport_type: sse
    url: https://mcp.example.com
    headers:
      Authorization: "Bearer <%= ENV['MCP_TOKEN'] %>"  # Shared token
```

### After (Per-User OAuth)
```ruby
# User connects via browser once
# Each user gets their own token with their own permissions
# Background jobs use user-specific tokens

class AiJob < ApplicationJob
  def perform(user_id, task)
    user = User.find(user_id)
    client = McpClient.for(user)  # User's token!
    # ... task executes with user's permissions ...
  end
end
```

## Next Steps

1. **Run the generator:**
   ```bash
   rails generate ruby_llm:mcp:oauth:install
   ```

2. **Customize the flow** for your app's UX

3. **Add to onboarding** or settings page

4. **Test with development MCP server**

5. **Deploy to production** with proper monitoring

## Related Documentation

- [OAuth 2.1 Implementation]({% link oauth.md %}) - Low-level OAuth details
- [Rails Integration]({% link guides/rails-integration.md %}) - Basic Rails setup
- [Background Jobs]({% link guides/background-jobs.md %}) - Job patterns
- [Security]({% link guides/security.md %}) - Security best practices

---

**Generated with RubyLLM MCP** • [Report Issues](https://github.com/patvice/ruby_llm-mcp/issues)
