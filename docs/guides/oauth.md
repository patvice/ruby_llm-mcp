---
layout: default
title: OAuth 2.1 Authentication
parent: Guides
nav_order: 5
description: "Complete OAuth 2.1 implementation with PKCE, dynamic registration, and automatic token refresh"
---

# OAuth 2.1 Authentication
{: .no_toc }

{: .label .label-green }
0.8+

Comprehensive OAuth 2.1 support for MCP servers with automatic token management, browser-based authentication, and pluggable storage.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Features
{: .label .label-green }
0.8+

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
{: .label .label-green }
0.8+

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
│  (SSE, StreamableHTTP)              │
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
{: .label .label-green }
0.8+

### Browser-Based OAuth (Simplest)

The easiest way to use OAuth with MCP - storage automatically shared:

```ruby
require "ruby_llm/mcp"

# Create client with OAuth config
client = RubyLLM::MCP.client(
  name: "oauth-server",
  transport_type: :sse,
  start: false,
  config: {
    url: "https://mcp.example.com/api",
    oauth: { scope: "mcp:read mcp:write" }
  }
)

# Authenticate via browser - storage automatically shared
client.oauth(type: :browser).authenticate

# Use client normally
client.start
tools = client.tools
puts "Available tools: #{tools.map(&:name).join(', ')}"
```

### Manual Authorization Flow (No Browser)

For headless environments:

```ruby
require "ruby_llm/mcp"

# Create client with OAuth config
client = RubyLLM::MCP.client(
  name: "oauth-server",
  transport_type: :sse,
  start: false,
  config: {
    url: "https://mcp.example.com/api",
    oauth: { scope: "mcp:read mcp:write" }
  }
)

# Get authorization URL
auth_url = client.oauth(type: :standard).start_authorization_flow
puts "Visit: #{auth_url}"

# After user authorizes, complete the flow
code = "authorization_code_from_callback"
state = "state_from_callback"
client.oauth.complete_authorization_flow(code, state)

# Use client normally
client.start
tools = client.tools
```

### Passing OAuth Provider Instance

You can also create the OAuth provider separately and pass it to the client:

```ruby
require "ruby_llm/mcp"

# Create and authenticate OAuth provider
oauth = RubyLLM::MCP::Auth.create_oauth(
  "https://mcp.example.com/api",
  type: :browser,
  scope: "mcp:read mcp:write"
)
oauth.authenticate

# Pass provider to client - storage automatically shared
client = RubyLLM::MCP.client(
  name: "oauth-server",
  transport_type: :sse,
  config: {
    url: "https://mcp.example.com/api",
    oauth: oauth
  }
)

# Use normally
tools = client.tools
puts "Available tools: #{tools.map(&:name).join(', ')}"
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
{: .label .label-green }
0.8+

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
{: .label .label-green }
0.8+

### Basic OAuth Client

The OAuth flow is the same regardless of transport type (SSE or StreamableHTTP):

```ruby
require "ruby_llm/mcp"

# Create client with OAuth config
client = RubyLLM::MCP.client(
  name: "oauth-server",
  transport_type: :sse,  # or :streamable
  start: false,
  config: {
    url: "https://mcp.example.com/api",
    oauth: { scope: "mcp:read mcp:write" }
  }
)

# Authenticate via browser
client.oauth(type: :browser).authenticate

# Use client normally
client.start
tools = client.tools
puts "Available tools: #{tools.map(&:name).join(', ')}"
```

### Manual Authorization Flow

For headless environments or when you need manual control:

```ruby
require "ruby_llm/mcp"

client = RubyLLM::MCP.client(
  name: "manual-auth",
  transport_type: :sse,
  start: false,
  config: {
    url: "https://mcp.example.com/api",
    oauth: { scope: "mcp:read" }
  }
)

# Get authorization URL
oauth = client.oauth(type: :standard)
auth_url = oauth.start_authorization_flow

puts "Visit: #{auth_url}"
puts "Enter authorization code:"
code = gets.chomp

puts "Enter state parameter:"
state = gets.chomp

# Complete authorization
oauth.complete_authorization_flow(code, state)

# Use client
client.start
tools = client.tools
```

## Browser-Based Authentication
{: .label .label-green }
0.8+

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

You can customize the HTML pages shown to users after OAuth authentication via the global configuration:

```ruby
RubyLLM::MCP.configure do |config|
  # Static HTML or a Proc that generates HTML
  config.oauth.browser_success_page = "<html><body><h1>Welcome!</h1></body></html>"

  # Error page receives the error message
  config.oauth.browser_error_page = ->(error_msg) {
    "<html><body><h1>Error:</h1><p>#{CGI.escapeHTML(error_msg)}</p></body></html>"
  }
end

# All browser OAuth providers will use these custom pages
browser_oauth = RubyLLM::MCP::Auth.create_oauth(
  "https://api.example.com",
  type: :browser,
  callback_port: 8080,
  scope: "mcp:read mcp:write"
)
```

## Custom Storage
{: .label .label-green }
0.8+

The default in-memory storage works for single-user applications, but production applications typically need persistent storage. Custom storage is especially important when:

- **Multi-user applications**: Each user needs their own OAuth tokens
- **Distributed systems**: Tokens must be shared across multiple processes/servers
- **Token persistence**: Tokens should survive application restarts
- **User-specific configuration**: Each user may have different MCP server configurations

### Storage Interface

Implement these methods for custom storage:

```ruby
class CustomStorage
  # Token storage - stores access/refresh tokens
  def get_token(server_url); end
  def set_token(server_url, token); end

  # Client registration storage - stores client_id and client_secret
  def get_client_info(server_url); end
  def set_client_info(server_url, client_info); end

  # Server metadata caching - stores OAuth server discovery metadata
  def get_server_metadata(server_url); end
  def set_server_metadata(server_url, metadata); end

  # PKCE state management (temporary) - only needed during auth flow
  def get_pkce(server_url); end
  def set_pkce(server_url, pkce); end
  def delete_pkce(server_url); end

  # State parameter management (temporary) - only needed during auth flow
  def get_state(server_url); end
  def set_state(server_url, state); end
  def delete_state(server_url); end
end
```

### Using Storage with Clients

When you pass a storage instance to a client, the OAuth provider automatically uses it for all token operations:

```ruby
# User-specific storage example
class UserOAuthStorage
  def initialize(user_id)
    @user_id = user_id
    @redis = Redis.new
  end

  def get_token(server_url)
    key = "user:#{@user_id}:oauth:#{server_url}:token"
    data = @redis.get(key)
    data ? RubyLLM::MCP::Auth::Token.from_h(JSON.parse(data, symbolize_names: true)) : nil
  end

  def set_token(server_url, token)
    key = "user:#{@user_id}:oauth:#{server_url}:token"
    @redis.set(key, token.to_h.to_json)
    @redis.expire(key, 86400) # 24 hours
  end

  # Implement remaining methods...
end

# Create client with user-specific storage
user = User.find(params[:user_id])
storage = UserOAuthStorage.new(user.id)

client = RubyLLM::MCP.client(
  name: "user-server",
  transport_type: :sse,
  start: false,
  config: {
    url: user.mcp_server_url,  # From user's database
    oauth: {
      storage: storage,          # User-specific storage
      scope: user.oauth_scope    # From user's preferences
    }
  }
)

# Authenticate (only needed once per user)
client.oauth(type: :browser).authenticate

# Future requests automatically use stored tokens
client.start
tools = client.tools
```
### Simple Redis Storage Example

An example of a simple Redis storage implementation that doesn't need per-user storage:

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

  # Implement remaining methods (get_client_info, set_client_info, etc.)...
end

# Use shared Redis storage
client = RubyLLM::MCP.client(
  name: "redis-backed",
  transport_type: :sse,
  start: false,
  config: {
    url: "https://mcp.example.com",
    oauth: {
      storage: RedisOAuthStorage.new,
      scope: "mcp:read mcp:write"
    }
  }
)

client.oauth(type: :browser).authenticate
client.start
```

### Complete Database Implementation

See [Rails OAuth Integration Guide]({% link guides/rails-oauth.md %}) for a complete multi-user database storage implementation with migrations, models, and controllers.

## Security Considerations
{: .label .label-green }
0.8+

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
{: .label .label-green }
0.8+

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

begin
  tools = client.tools
rescue RubyLLM::MCP::Errors::AuthenticationRequiredError => e
  puts "Authentication required: #{e.message}"

  # Trigger browser OAuth flow using client.oauth
  token = client.oauth(type: :browser).authenticate

  puts "Authenticated! Token expires: #{token.expires_at}"

  # Retry the operation
  client.restart!
  tools = client.tools
end

puts "Available tools: #{tools.map(&:name).join(', ')}"
```

## Advanced Topics
{: .label .label-green }
0.8+

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

## Next Steps

1. **Single-user apps**: Use `BrowserOAuthProvider` class directly or use the factory method `Auth.create_oauth`
2. **Multi-user apps**: Use Rails OAuth integration
3. **Production**: Implement custom storage (Redis, Database)
4. **Security**: Enable debug logging during development

## Related Documentation

- [Rails OAuth Integration]({% link guides/rails-oauth.md %}) - Multi-user setup
- [Rails Integration]({% link guides/rails-integration.md %}) - Basic Rails setup
- [Configuration]({% link configuration.md %}) - Transport configuration

---

**RubyLLM MCP** • [GitHub](https://github.com/patvice/ruby_llm-mcp) • [Report Issues](https://github.com/patvice/ruby_llm-mcp/issues)
