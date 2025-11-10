---
layout: default
title: OAuth 2.1 Authentication
parent: Guides
nav_order: 8
description: "Complete OAuth 2.1 implementation with PKCE, dynamic registration, and automatic token refresh"
---

# OAuth 2.1 Authentication
{: .no_toc }

Comprehensive OAuth 2.1 support for MCP servers with automatic token management, browser-based authentication, and pluggable storage.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Features

### OAuth 2.1 Compliance

- ✅ **PKCE (RFC 7636)**: Mandatory Proof Key for Code Exchange with S256 (SHA256)
- ✅ **Dynamic Client Registration (RFC 7591)**: Automatic client registration with OAuth servers
- ✅ **Server Discovery (RFC 8414)**: Automatic authorization server metadata discovery
- ✅ **Protected Resource Metadata (RFC 9728)**: Support for delegated authorization servers
- ✅ **Resource Indicators (RFC 8707)**: Token binding to specific MCP servers
- ✅ **State Parameter**: CSRF protection for authorization flows
- ✅ **Automatic Token Refresh**: Proactive token refresh with 5-minute buffer
- ✅ **Secure Token Storage**: Pluggable storage with in-memory default

### Transport Support

| Transport | OAuth Support | Details |
|-----------|---------------|---------|
| **SSE** | ✅ Full support | Event streams and message endpoints |
| **StreamableHTTP** | ✅ Full support | All HTTP requests with session management |
| **Stdio** | N/A | Local process communication (no auth needed) |

## Architecture

### Core Components

```
┌─────────────────────────────────────┐
│         OAuth Provider              │
│  (Discovery, Registration, Tokens)  │
├─────────────────────────────────────┤
│         Browser OAuth               │
│  (Local callback server)            │
├─────────────────────────────────────┤
│         Storage Layer               │
│  (Tokens, Client Info, Metadata)    │
├─────────────────────────────────────┤
│         Transport Layer             │
│  (SSE, StreamableHTTP)             │
└─────────────────────────────────────┘
```

### OAuth Flow

```
1. Client Configuration → OAuth Provider Creation
2. Server Discovery → Authorization Server Metadata
3. Client Registration → Client ID & Client Secret
4. Authorization Request → PKCE + State Generation
5. User Authorization → Browser/Manual
6. Token Exchange → Access Token + Refresh Token
7. API Requests → Automatic Token Refresh
```

## Quick Start

### Basic Configuration

Add OAuth configuration to your MCP client:

```ruby
require "ruby_llm/mcp"

client = RubyLLM::MCP.client(
  name: "oauth-mcp-server",
  transport_type: :sse,  # or :streamable
  config: {
    url: "https://mcp.example.com/api",
    oauth: {
      redirect_uri: "http://localhost:8080/callback",
      scope: "mcp:read mcp:write"
    }
  }
)
```

### File-Based Configuration

Create `config/mcp_servers.yml`:

```yaml
mcp_servers:
  protected_server:
    transport_type: streamable
    url: https://mcp.example.com/api
    oauth:
      redirect_uri: http://localhost:8080/callback
      scope: mcp:read mcp:write
```

Load configuration:

```ruby
RubyLLM.configure do |config|
  config.config_path = "config/mcp_servers.yml"
end

RubyLLM::MCP.establish_connection
```

## Configuration Options

### OAuth Configuration

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `redirect_uri` | String | No | Callback URL for authorization (default: `http://localhost:8080/callback`) |
| `scope` | String | No | OAuth scopes to request (e.g., `"mcp:read mcp:write"`) |
| `storage` | Object | No | Custom storage implementation (default: in-memory) |

### Environment Variables

Use ERB in configuration files:

```yaml
mcp_servers:
  production_server:
    transport_type: streamable
    url: <%= ENV['MCP_SERVER_URL'] %>
    oauth:
      redirect_uri: <%= ENV['OAUTH_REDIRECT_URI'] %>
      scope: <%= ENV['OAUTH_SCOPE'] %>
```

## Usage Examples

### SSE Client with OAuth

```ruby
require "ruby_llm/mcp"
require "ruby_llm/mcp/auth/browser_oauth"

# Create client with OAuth
client = RubyLLM::MCP.client(
  name: "secure-server",
  transport_type: :sse,
  start: false,
  config: {
    url: "https://mcp.example.com/sse",
    oauth: {
      redirect_uri: "http://localhost:8080/callback",
      scope: "mcp:read mcp:write"
    }
  }
)

# Authenticate via browser using factory method
browser_oauth = RubyLLM::MCP::Auth.create_oauth(
  "https://api.example.com/mcp/sse",
  type: :browser,
  callback_port: 8080,
  scope: "mcp:sse"
)

token = browser_oauth.authenticate(timeout: 300)

puts "Successfully authenticated!"
client.start

# Use normally - OAuth automatic
tools = client.tools
puts "Available tools: #{tools.map(&:name).join(', ')}"
```

### StreamableHTTP with OAuth

```ruby
client = RubyLLM::MCP.client(
  name: "streamable-server",
  transport_type: :streamable,
  start: false,
  config: {
    url: "https://api.example.com/mcp",
    oauth: {
      redirect_uri: "http://localhost:9000/callback",
      scope: "mcp:full"
    }
  }
)

# Authenticate using factory method
browser_oauth = RubyLLM::MCP::Auth.create_oauth(
  "https://api.example.com/mcp",
  type: :browser,
  callback_port: 9000,
  scope: "mcp:full"
)
browser_oauth.authenticate

# Use client
client.start
result = client.tool("search").execute(params: { query: "Ruby MCP" })
```

### Manual Authorization Flow

For scenarios without browser access:

```ruby
client = RubyLLM::MCP.client(
  name: "manual-auth",
  transport_type: :sse,
  start: false,
  config: {
    url: "https://mcp.example.com/api",
    oauth: { scope: "mcp:read" }
  }
)

transport = client.instance_variable_get(:@coordinator).send(:transport)
oauth_provider = transport.oauth_provider

# Get authorization URL
auth_url = oauth_provider.start_authorization_flow

puts "\nPlease visit this URL to authorize:"
puts auth_url
puts "\nEnter the 'code' parameter from callback:"
code = gets.chomp

puts "Enter the 'state' parameter:"
state = gets.chomp

# Complete authorization
token = oauth_provider.complete_authorization_flow(code, state)
client.start
```

## Browser-Based Authentication

The `BrowserOAuthProvider` class provides complete browser-based OAuth:

### Features

- **Automatic Browser Opening**: Opens default browser to authorization URL
- **Local Callback Server**: Pure Ruby TCP server (no external dependencies)
- **Beautiful UI**: Styled HTML success/error pages with RubyLLM MCP branding
- **Custom Pages**: Optional custom success/error pages for your branding
- **Cross-Platform**: Supports macOS, Linux, Windows
- **Timeout Support**: Configurable timeout for user authorization
- **Thread-Safe**: Safe for concurrent use

### Usage

```ruby
require "ruby_llm/mcp/auth/browser_oauth"

browser_oauth = RubyLLM::MCP::Auth.create_oauth(
  "https://mcp.example.com",
  type: :browser,
  callback_port: 8080,
  scope: "mcp:read mcp:write"
)

begin
  token = browser_oauth.authenticate(
    timeout: 300,              # 5 minutes
    auto_open_browser: true
  )

  puts "Access token: #{token.access_token}"
  puts "Expires at: #{token.expires_at}"
rescue RubyLLM::MCP::Errors::TimeoutError
  puts "Authorization timed out"
rescue RubyLLM::MCP::Errors::TransportError => e
  puts "Authorization failed: #{e.message}"
end
```

### Custom Success/Error Pages

You can customize the HTML pages shown to users after OAuth authentication:

```ruby
browser_oauth = RubyLLM::MCP::Auth.create_oauth(
  "https://api.example.com",
  type: :browser,
  callback_port: 8080,
  scope: "mcp:read mcp:write",
  pages: {
    # Static HTML or a Proc that generates HTML
    success_page: "<html><body><h1>Welcome!</h1></body></html>",

    # Error page receives the error message
    error_page: ->(error_msg) {
      "<html><body><h1>Error:</h1><p>#{CGI.escapeHTML(error_msg)}</p></body></html>"
    }
  }
)
```

## Custom Storage

### Storage Interface

Implement these methods for custom storage:

```ruby
class CustomStorage
  # Token storage
  def get_token(server_url); end
  def set_token(server_url, token); end

  # Client registration storage
  def get_client_info(server_url); end
  def set_client_info(server_url, client_info); end

  # Server metadata caching
  def get_server_metadata(server_url); end
  def set_server_metadata(server_url, metadata); end

  # PKCE state management (temporary)
  def get_pkce(server_url); end
  def set_pkce(server_url, pkce); end
  def delete_pkce(server_url); end

  # State parameter management (temporary)
  def get_state(server_url); end
  def set_state(server_url, state); end
  def delete_state(server_url); end
end
```

### Redis Storage Example

```ruby
require "redis"
require "json"

class RedisOAuthStorage
  def initialize(redis_url = ENV["REDIS_URL"])
    @redis = Redis.new(url: redis_url)
  end

  def get_token(server_url)
    data = @redis.get("oauth:token:#{server_url}")
    data ? RubyLLM::MCP::Auth::Token.from_h(JSON.parse(data, symbolize_names: true)) : nil
  end

  def set_token(server_url, token)
    @redis.set("oauth:token:#{server_url}", token.to_h.to_json)
    @redis.expire("oauth:token:#{server_url}", 86400)
  end

  # Implement remaining methods...
end

# Use custom storage
client = RubyLLM::MCP.client(
  name: "redis-backed",
  transport_type: :sse,
  config: {
    url: "https://mcp.example.com",
    oauth: {
      storage: RedisOAuthStorage.new,
      scope: "mcp:read"
    }
  }
)
```

### Database Storage Example

See [Rails OAuth Integration Guide]({% link guides/rails-oauth.md %}) for complete database storage implementation.

## Security Considerations

### PKCE (Proof Key for Code Exchange)

All OAuth flows use PKCE with S256 (SHA256):

- **Code Verifier**: 32 bytes of cryptographically secure random data
- **Code Challenge**: SHA256 hash of the verifier
- **Protection**: Prevents authorization code interception attacks

### State Parameter

CSRF protection via state parameter:

- **Generation**: 32 bytes of random data (base64url encoded)
- **Validation**: Strict equality check on callback
- **Storage**: Temporary storage, deleted after flow completion

### Token Security

- **Automatic Refresh**: Tokens refreshed proactively (5-minute buffer before expiration)
- **Secure Storage**: Tokens stored securely via pluggable storage interface
- **HTTPS Only**: OAuth flows require HTTPS endpoints (except localhost)
- **Resource Binding**: RFC 8707 resource indicators prevent token reuse across servers

### URL Normalization

Server URLs normalized to prevent token confusion:

```
https://MCP.EXAMPLE.COM:443/api/  → https://mcp.example.com/api
http://example.com:80             → http://example.com
```

## Troubleshooting

### Port Already in Use

```ruby
browser_oauth = RubyLLM::MCP::Auth.create_oauth(
  "https://mcp.example.com",
  type: :browser,
  callback_port: 8081,  # Try different port
  scope: "mcp:read mcp:write"
)
```

### Browser Doesn't Open

```ruby
token = browser_oauth.authenticate(auto_open_browser: false)
# Manually open the displayed URL
```

### Token Refresh Fails

```ruby
token = oauth_provider.access_token
if token&.refresh_token
  puts "Refresh token present"
else
  puts "No refresh token - re-authentication required"
end
```

### Discovery Fails

```ruby
# Check discovery URLs
discovery_url = "https://mcp.example.com/.well-known/oauth-authorization-server"
# Verify endpoint exists
```

### Redirect URI Mismatch

Ensure exact match (no trailing slash, correct protocol):

```ruby
# ✅ Correct
"http://localhost:8080/callback"

# ❌ Wrong
"http://localhost:8080/callback/"  # Trailing slash
"http://127.0.0.1:8080/callback"   # Different host
```

### Handling Authentication Required Errors

When a server requires OAuth authentication, it returns HTTP 401. Handle this to trigger OAuth flow:

```ruby
require "ruby_llm/mcp"
require "ruby_llm/mcp/auth/browser_oauth"

begin
  tools = client.tools
rescue RubyLLM::MCP::Errors::AuthenticationRequiredError => e
  puts "Authentication required: #{e.message}"

  # Trigger browser OAuth flow
  browser_oauth = RubyLLM::MCP::Auth.create_oauth(
    "https://mcp.example.com",
    type: :browser,
    callback_port: 8080,
    scope: "mcp:read mcp:write"
  )
  token = browser_oauth.authenticate

  puts "Authenticated! Token expires: #{token.expires_at}"

  # Retry the operation
  client.restart!
  tools = client.tools
end

puts "Available tools: #{tools.map(&:name).join(', ')}"
```

## Advanced Topics

### Custom OAuth Provider

```ruby
require "ruby_llm/mcp/auth/oauth_provider"

provider = RubyLLM::MCP::Auth::OAuthProvider.new(
  server_url: "https://mcp.example.com",
  redirect_uri: "http://localhost:8080/callback",
  scope: "custom:scope",
  logger: Logger.new($stdout, level: Logger::DEBUG),
  storage: CustomStorage.new
)

# Manual flow control
auth_url = provider.start_authorization_flow
# ... user authorization ...
token = provider.complete_authorization_flow(code, state)
```

### Token Introspection

```ruby
token = oauth_provider.access_token

if token
  puts "Valid: #{!token.expired?}"
  puts "Expires soon: #{token.expires_soon?}"
  puts "Expires at: #{token.expires_at}"
  puts "Scope: #{token.scope}"
end
```

### Debug Logging

```ruby
RubyLLM.configure do |config|
  config.log_level = Logger::DEBUG
end

# Or environment variable
ENV["RUBYLLM_MCP_DEBUG"] = "1"
```

### Client Credentials Flow

For application-to-application authentication without user interaction:

```ruby
require "ruby_llm/mcp"
require "ruby_llm/mcp/auth/oauth_provider"

# Create OAuth provider with client credentials grant
provider = RubyLLM::MCP::Auth::OAuthProvider.new(
  server_url: "https://api.example.com/mcp",
  scope: "mcp:read mcp:write",
  grant_type: :client_credentials
)

# Authenticate with client credentials (no browser needed)
token = provider.client_credentials_flow
puts "Authenticated! Token expires: #{token.expires_at}"

# Use with MCP client
client = RubyLLM::MCP.client(
  name: "app-client",
  transport_type: :streamable,
  config: {
    url: "https://api.example.com/mcp",
    oauth: {
      grant_type: :client_credentials,
      scope: "mcp:read mcp:write"
    }
  }
)

# Manually authenticate before using client
transport_wrapper = client.instance_variable_get(:@coordinator).send(:transport)
actual_transport = transport_wrapper.transport_protocol
oauth_provider = actual_transport.oauth_provider

# Perform client credentials authentication
token = oauth_provider.client_credentials_flow
puts "Token obtained: #{token.access_token[0..10]}..."

# Start the client (now authenticated)
client.start

# Use the client
puts "Available tools: #{client.tools.map(&:name).join(', ')}"
```

**Note**: Client credentials flow requires:
- Server support for `client_credentials` grant type
- A `client_secret` from dynamic registration (confidential client)
- Application-level authorization (no user context)

**Configuration Options**:

```ruby
# In client config
config: {
  oauth: {
    grant_type: :client_credentials,  # Default: :authorization_code
    scope: "api:read api:write"
  }
}
```

## Multi-User Applications

For Rails applications with multiple users, see:
- **[Rails OAuth Integration]({% link guides/rails-oauth.md %})** - Complete multi-tenant setup with customizable generator

### Rails Generator Features

The OAuth generator supports full customization for different Rails architectures:

```bash
# Basic installation
rails generate ruby_llm:mcp:oauth:install

# Custom user model (Account, Member, etc.)
rails generate ruby_llm:mcp:oauth:install Account

# Namespaced (Admin panel, multi-tenant)
rails generate ruby_llm:mcp:oauth:install User --namespace=Admin

# With options
rails generate ruby_llm:mcp:oauth:install User \
  --namespace=Admin \
  --controller-name=OAuthConnectionsController \
  --skip-routes
```

The generator automatically:
- Creates migrations with proper foreign keys for your user model
- Generates models with correct associations
- Updates controllers with your authentication methods
- Injects routes (unless `--skip-routes`)
- Customizes all service objects and jobs

## Next Steps

1. **Single-user apps**: Use `BrowserOAuthProvider` class directly or use the factory method `Auth.create_oauth`
2. **Multi-user apps**: Use Rails OAuth integration
3. **Production**: Implement custom storage (Redis, Database)
4. **Security**: Enable debug logging during development

## Related Documentation

- [Rails OAuth Integration]({% link guides/rails-oauth.md %}) - Multi-user setup
- [Rails Integration]({% link guides/rails-integration.md %}) - Basic Rails setup
- [Transports]({% link guides/transports.md %}) - Transport configuration

---

**RubyLLM MCP** • [GitHub](https://github.com/patvice/ruby_llm-mcp) • [Report Issues](https://github.com/patvice/ruby_llm-mcp/issues)
