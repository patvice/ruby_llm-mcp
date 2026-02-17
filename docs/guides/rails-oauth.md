---
layout: default
title: Rails OAuth Integration
parent: Advanced
nav_order: 7
description: "Multi-user OAuth authentication for Rails apps with background jobs and per-user MCP permissions"
nav_exclude: true
---

# Rails OAuth Integration
{: .no_toc }

{: .label .label-green }
0.8+

Complete guide for implementing multi-tenant OAuth authentication in Rails applications, enabling per-user MCP server connections with background job support.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview
{: .label .label-green }
0.8+

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
  ensure
    client&.stop
  end
end
```

## Generator Options

| Option | Description | Example |
|--------|-------------|---------|
| `UserModel` | Authentication model name | `Account`, `Member`, `Admin` |
| `--namespace` | Namespace for controllers/views | `--namespace=Admin` |
| `--controller-name` | Custom controller name | `--controller-name=OAuthConnectionsController` |
| `--skip-routes` | Don't inject routes automatically | `--skip-routes` |
| `--skip-views` | Don't generate view files | `--skip-views` |

## Architecture

### Database Schema

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

### Key Models

**McpOauthCredential** - Stores encrypted OAuth tokens per user/server
- `encrypts :token_data` - Uses Rails encryption
- `token` / `token=` - Serializes Token objects
- `expired?` / `expires_soon?` - Token status helpers

**McpOauthState** - Temporary state for OAuth flow
- Stores PKCE verifier (encrypted)
- Auto-expires after OAuth flow completes
- Cleanup job removes expired states

**McpTokenStorage** - Concern providing token storage interface
- Automatically included via `UserMcpOauth`
- Provides `mcp_token_storage(server_url)` method
- Implements OAuth storage interface for MCP client

### McpClient Factory

The generator creates an `McpClient` class for creating per-user MCP clients:

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
end
```

## Usage Patterns

### Background Jobs (Recommended)

```ruby
class AiAnalysisJob < ApplicationJob
  queue_as :default

  def perform(user_id, analysis_params)
    user = User.find(user_id)
    client = McpClient.for(user)

    tools = client.tools
    chat = RubyLLM.chat(provider: "anthropic/claude-sonnet-4")
      .with_tools(*tools)

    result = chat.ask(analysis_params[:query])
    # Save results...
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

### Inline (Synchronous)

```ruby
class SearchController < ApplicationController
  def create
    ensure_mcp_connected!
    client = McpClient.for(current_user)
    result = client.tool("search").execute(params: { query: params[:query] })
    render json: { results: result }
  ensure
    client&.stop
  end
end
```

### Multi-Server Support

```ruby
# app/models/mcp_server.rb
class McpServer
  SERVERS = {
    github: { url: ENV["GITHUB_MCP_URL"], scopes: "mcp:repos mcp:issues" },
    slack: { url: ENV["SLACK_MCP_URL"], scopes: "mcp:messages mcp:channels" }
  }.freeze

  def self.for(key)
    SERVERS[key.to_sym]
  end
end

# Usage in jobs
class MultiServerJob < ApplicationJob
  def perform(user_id, task)
    user = User.find(user_id)
    github = McpClient.for(user, server_url: McpServer.for(:github)[:url])
    slack = McpClient.for(user, server_url: McpServer.for(:slack)[:url])
    # Use both clients...
  end
end
```

## Security

### 1. Encrypt Sensitive Data

```ruby
# config/application.rb
config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
```

Models automatically use `encrypts :token_data` and `encrypts :client_info_data`.

### 2. Rate Limiting

Rails 8+ includes built-in rate limiting. The generator automatically adds protection:

```ruby
# app/controllers/mcp_connections_controller.rb
class McpConnectionsController < ApplicationController
  # Prevent burst requests - max 5 per minute
  rate_limit to: 5, within: 1.minute, only: [:connect, :callback],
             by: -> { current_user.id }

  # Prevent abuse - max 20 per day
  rate_limit to: 20, within: 1.day, only: [:connect, :callback],
             by: -> { current_user.id }
end
```

**For Rails 7 and earlier**, use Rack::Attack or similar.

### 3. Validate Redirect URIs

Ensure redirect URIs match exactly what's configured in your MCP OAuth server (no trailing slashes, exact protocol).

## Error Handling

```ruby
class AiTaskJob < ApplicationJob
  def perform(user_id, task)
    user = User.find(user_id)

    begin
      client = McpClient.for(user)
      # ... execute task ...
    rescue McpClient::NotAuthenticatedError
      # User not connected - notify them
      notify_auth_required(user)
    rescue RubyLLM::MCP::Errors::TransportError => e
      if e.message.include?("401") || e.message.include?("Unauthorized")
        # Token invalid - notify user to reconnect
        notify_reauth_required(user)
      else
        raise
      end
    ensure
      client&.stop
    end
  end
end
```

## Troubleshooting

### OAuth flow fails with "invalid_redirect_uri"

Ensure redirect URI matches exactly what's configured in MCP OAuth server (no trailing slash, exact protocol).

### Jobs fail with 401 Unauthorized

Check if credential has refresh token. If not, user must re-authenticate:

```ruby
credential = user.mcp_oauth_credentials.first
if credential.token.refresh_token.nil?
  # User must re-authenticate
end
```

### Session lost during OAuth

Increase session timeout in `config/initializers/session_store.rb`:

```ruby
Rails.application.config.session_store :cookie_store,
  key: '_myapp_session',
  expire_after: 30.minutes  # OAuth flow timeout
```

### Deployment Checklist

- [ ] Run migrations: `rails db:migrate`
- [ ] Set encryption keys in production
- [ ] Configure allowed redirect URIs
- [ ] Set up background job for token refresh (optional)
- [ ] Test OAuth flow in staging
- [ ] Set up cleanup job for expired OAuth states

### Cleanup Jobs

The generator creates a cleanup job for expired OAuth states. Schedule it to run daily:

```ruby
# config/schedule.rb (whenever gem)
every 1.day, at: "3:00 am" do
  runner "CleanupExpiredOauthStatesJob.perform_later"
end
```

## Related Documentation

- [OAuth 2.1 Implementation]({% link guides/oauth.md %}) - Low-level OAuth details
- [Rails Integration]({% link guides/rails-integration.md %}) - Basic Rails setup

---

**Generated with RubyLLM MCP** • [Report Issues](https://github.com/patvice/ruby_llm-mcp/issues)
